defmodule Newton.OAuth do
  @moduledoc """
  Single-user OAuth 2.1 authorization server: dynamic client registration,
  PKCE authorization-code grants, rotating refresh tokens, and bearer
  verification for the MCP endpoint.
  """

  import Ecto.Query, warn: false

  alias Newton.OAuth.Client
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
end
