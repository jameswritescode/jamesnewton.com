defmodule Newton.OAuth do
  @moduledoc """
  Single-user OAuth 2.1 authorization server: dynamic client registration,
  PKCE authorization-code grants, rotating refresh tokens, and bearer
  verification for the MCP endpoint.
  """

  import Ecto.Query, warn: false

  alias Newton.OAuth.Client
  alias Newton.OAuth.Grant
  alias Newton.Repo

  @doc "Random 32-byte URL-safe secret (codes, tokens, client secrets)."
  @spec generate_secret() :: String.t()
  def generate_secret do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @spec hash(String.t()) :: binary()
  def hash(value), do: :crypto.hash(:sha256, value)

  @spec register_client(map()) ::
          {:ok, {%Client{}, String.t() | nil}} | {:error, Ecto.Changeset.t()}
  def register_client(attrs) do
    changeset = Client.registration_changeset(%Client{}, attrs)

    secret =
      if Ecto.Changeset.get_field(changeset, :token_endpoint_auth_method) == "none",
        do: nil,
        else: generate_secret()

    changeset
    |> Ecto.Changeset.put_change(:client_id, generate_secret())
    |> Ecto.Changeset.put_change(:client_secret_hash, secret && hash(secret))
    |> Repo.insert()
    |> case do
      {:ok, client} -> {:ok, {client, secret}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec get_client(String.t()) :: %Client{} | nil
  def get_client(client_id) when is_binary(client_id) do
    Repo.get_by(Client, client_id: client_id)
  end

  def get_client(_), do: nil

  @spec authenticate_client(String.t() | nil, String.t() | nil) ::
          {:ok, %Client{}} | {:error, :invalid_client}
  def authenticate_client(client_id, secret) do
    Newton.Telemetry.span(:oauth, :grant, %{operation: :authenticate_client}, fn ->
      result = do_authenticate_client(client_id, secret)
      telemetry_result = if match?({:ok, _}, result), do: :ok, else: :invalid_client
      {result, %{operation: :authenticate_client, result: telemetry_result}}
    end)
  end

  defp do_authenticate_client(client_id, secret) do
    client = client_id && get_client(client_id)

    cond do
      is_nil(client) ->
        {:error, :invalid_client}

      client.token_endpoint_auth_method == "none" ->
        if is_nil(secret), do: {:ok, client}, else: {:error, :invalid_client}

      is_binary(secret) and is_binary(client.client_secret_hash) ->
        if Plug.Crypto.secure_compare(hash(secret), client.client_secret_hash),
          do: {:ok, client},
          else: {:error, :invalid_client}

      true ->
        {:error, :invalid_client}
    end
  end

  @code_ttl_seconds 300
  @access_ttl_seconds 3600
  @refresh_ttl_seconds 60 * 60 * 24 * 30
  @subject "site-admin"

  @type token_response :: %{
          access_token: String.t(),
          token_type: String.t(),
          expires_in: non_neg_integer(),
          refresh_token: String.t()
        }

  @doc "The audience every token is bound to: this site's MCP endpoint."
  @spec canonical_resource() :: String.t()
  def canonical_resource, do: base_url() <> "/mcp"

  # Derived from endpoint config, not the running endpoint: plan 2's MCP child
  # spec evaluates this before NewtonWeb.Endpoint has started.
  defp base_url do
    conf = Application.get_env(:newton, NewtonWeb.Endpoint, [])
    url = conf[:url] || []
    scheme = url[:scheme] || "http"
    host = url[:host] || "localhost"
    port = url[:port] || get_in(conf, [:http, :port]) || 4000
    URI.to_string(%URI{scheme: scheme, host: host, port: port})
  end

  @spec issue_code(%Client{}, String.t(), String.t(), String.t()) :: {:ok, String.t()}
  def issue_code(%Client{} = client, redirect_uri, code_challenge, resource)
      when is_binary(redirect_uri) and is_binary(code_challenge) and is_binary(resource) do
    unless redirect_uri in client.redirect_uris,
      do: raise(ArgumentError, "redirect_uri not registered for client")

    unless resource == canonical_resource(),
      do: raise(ArgumentError, "resource must be #{canonical_resource()}")

    code = generate_secret()

    %Grant{
      client_id: client.id,
      code_hash: hash(code),
      code_expires_at: expires_in(@code_ttl_seconds),
      code_challenge: code_challenge,
      redirect_uri: redirect_uri,
      resource: resource
    }
    |> Repo.insert!()

    {:ok, code}
  end

  @spec exchange_code(%Client{}, String.t(), String.t(), String.t()) ::
          {:ok, token_response()} | {:error, :invalid_grant}
  def exchange_code(%Client{} = client, code, redirect_uri, code_verifier)
      when is_binary(code) and is_binary(code_verifier) do
    Newton.Telemetry.span(:oauth, :grant, %{operation: :exchange_code}, fn ->
      code_hash = hash(code)
      grant = Repo.get_by(Grant, code_hash: code_hash)

      {result, telemetry_result} = do_exchange_code(client, grant, redirect_uri, code_verifier)
      {result, %{operation: :exchange_code, result: telemetry_result}}
    end)
  end

  def exchange_code(_, _, _, _), do: {:error, :invalid_grant}

  defp do_exchange_code(client, grant, redirect_uri, code_verifier) do
    cond do
      is_nil(grant) or not is_nil(grant.revoked_at) ->
        {{:error, :invalid_grant}, :invalid_grant}

      not is_nil(grant.code_used_at) ->
        revoke(grant)
        {{:error, :invalid_grant}, :reused_code}

      grant.client_id != client.id ->
        {{:error, :invalid_grant}, :invalid_grant}

      expired?(grant.code_expires_at) ->
        {{:error, :invalid_grant}, :invalid_grant}

      grant.redirect_uri != redirect_uri ->
        {{:error, :invalid_grant}, :invalid_grant}

      not pkce_valid?(grant.code_challenge, code_verifier) ->
        {{:error, :invalid_grant}, :invalid_grant}

      true ->
        exchange_code_transaction(grant)
    end
  end

  defp exchange_code_transaction(grant) do
    Repo.transaction(fn ->
      now_ts = now()
      refresh_expiry = expires_in(@refresh_ttl_seconds)

      {rows, _} =
        Repo.update_all(
          from(g in Grant,
            where: g.id == ^grant.id and is_nil(g.code_used_at)
          ),
          set: [
            code_used_at: now_ts,
            refresh_token_expires_at: refresh_expiry
          ]
        )

      if rows == 1 do
        issue_tokens(grant, %{code_used_at: now_ts})
      else
        revoke(grant)
        {:error, :reused}
      end
    end)
    |> case do
      {:ok, {:ok, tokens}} -> {{:ok, tokens}, :ok}
      {:ok, {:error, :reused}} -> {{:error, :invalid_grant}, :reused_code}
      {:error, _} -> {{:error, :invalid_grant}, :invalid_grant}
    end
  end

  @spec refresh(%Client{}, String.t()) :: {:ok, token_response()} | {:error, :invalid_grant}
  def refresh(%Client{} = client, refresh_token) when is_binary(refresh_token) do
    Newton.Telemetry.span(:oauth, :grant, %{operation: :refresh}, fn ->
      {result, telemetry_result} = do_refresh(client, refresh_token)
      {result, %{operation: :refresh, result: telemetry_result}}
    end)
  end

  def refresh(_, _), do: {:error, :invalid_grant}

  defp do_refresh(client, refresh_token) do
    hashed = hash(refresh_token)
    grant = active_grant_by(client, refresh_token_hash: hashed)

    cond do
      grant && not expired?(grant.refresh_token_expires_at) ->
        refresh_transaction(grant, hashed)

      grant ->
        {{:error, :invalid_grant}, :invalid_grant}

      true ->
        grant_with_reuse = active_grant_by(client, previous_refresh_token_hash: hashed)

        if grant_with_reuse do
          revoke(grant_with_reuse)
          {{:error, :invalid_grant}, :reused_refresh}
        else
          {{:error, :invalid_grant}, :invalid_grant}
        end
    end
  end

  defp refresh_transaction(grant, hashed) do
    Repo.transaction(fn ->
      new_refresh_token = generate_secret()
      new_refresh_hash = hash(new_refresh_token)

      {rows, _} =
        Repo.update_all(
          from(g in Grant,
            where: g.id == ^grant.id and g.refresh_token_hash == ^hashed and is_nil(g.revoked_at)
          ),
          set: [
            previous_refresh_token_hash: hashed,
            refresh_token_hash: new_refresh_hash
          ]
        )

      if rows == 1 do
        access_token = generate_secret()
        grant = Repo.get!(Grant, grant.id)

        grant
        |> Ecto.Changeset.change(%{
          access_token_hash: hash(access_token),
          access_token_expires_at: expires_in(@access_ttl_seconds)
        })
        |> Repo.update!()

        {:ok,
         %{
           access_token: access_token,
           token_type: "Bearer",
           expires_in: @access_ttl_seconds,
           refresh_token: new_refresh_token
         }}
      else
        {:error, :invalid_grant}
      end
    end)
    |> case do
      {:ok, {:ok, tokens}} -> {{:ok, tokens}, :ok}
      {:ok, {:error, :invalid_grant}} -> {{:error, :invalid_grant}, :invalid_grant}
      {:error, _} -> {{:error, :invalid_grant}, :invalid_grant}
    end
  end

  @spec verify_access_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def verify_access_token(token) when is_binary(token) and token != "" do
    grant =
      Repo.one(
        from g in Grant,
          where: g.access_token_hash == ^hash(token) and is_nil(g.revoked_at),
          preload: [:client]
      )

    if grant && not expired?(grant.access_token_expires_at) &&
         grant.resource == canonical_resource() do
      {:ok, %{"sub" => @subject, "aud" => grant.resource, "client_id" => grant.client.client_id}}
    else
      {:error, :invalid_token}
    end
  end

  def verify_access_token(_), do: {:error, :invalid_token}

  defp issue_tokens(%Grant{} = grant, extra_changes) do
    access_token = generate_secret()
    refresh_token = generate_secret()

    changes =
      Map.merge(extra_changes, %{
        access_token_hash: hash(access_token),
        access_token_expires_at: expires_in(@access_ttl_seconds),
        previous_refresh_token_hash: grant.refresh_token_hash,
        refresh_token_hash: hash(refresh_token)
      })

    grant |> Ecto.Changeset.change(changes) |> Repo.update!()

    {:ok,
     %{
       access_token: access_token,
       token_type: "Bearer",
       expires_in: @access_ttl_seconds,
       refresh_token: refresh_token
     }}
  end

  defp active_grant_by(%Client{id: client_id}, clause) do
    query = from(g in Grant, where: g.client_id == ^client_id and is_nil(g.revoked_at))

    Enum.reduce(clause, query, fn {field, value}, q ->
      from(g in q, where: field(g, ^field) == ^value)
    end)
    |> Repo.one()
  end

  defp revoke(%Grant{} = grant) do
    grant |> Ecto.Changeset.change(revoked_at: now()) |> Repo.update!()
  end

  defp pkce_valid?(challenge, verifier) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    Plug.Crypto.secure_compare(computed, challenge)
  end

  defp expired?(expires_at), do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp expires_in(seconds), do: DateTime.add(now(), seconds, :second)
end
