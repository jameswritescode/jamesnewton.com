# OAuth 2.1 Authorization Server Implementation Plan (1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A spec-faithful, single-user OAuth 2.1 authorization server (DCR + PKCE authorization-code + rotating refresh tokens) that will guard the MCP endpoint built in plan 2 of 2.

**Architecture:** `Newton.OAuth` (domain) owns clients, grants, hashing, PKCE, and token verification over two tables. Two thin web layers: `OAuthController` (metadata, register, token — JSON, no session) and `OAuthAuthorizationController` (authorize + consent — browser pipeline, behind the existing admin login).

**Tech Stack:** Phoenix 1.8, Ecto/Postgres, `:crypto` + `Plug.Crypto` (no new deps in this plan).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-17-mcp-server-oauth-design.md`
- All secrets (codes, access tokens, refresh tokens, client secrets) are random 32-byte values via `:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)`, stored SHA-256 hashed (`:crypto.hash(:sha256, value)`) — never plaintext
- PKCE `S256` only; `plain` and absent are rejected; comparison via `Plug.Crypto.secure_compare/2`
- Redirect URIs matched **exactly** against registration — no wildcards, no prefix matching; a redirect_uri failure renders an error page and never redirects
- Authorization codes: single-use, 5-minute expiry; **code reuse revokes the entire grant**
- Access tokens: 1-hour expiry. Refresh tokens: rotated every use, **reuse of a rotated refresh token revokes the grant**, 30-day absolute expiry (set at grant creation, never extended)
- Grant types: `authorization_code` and `refresh_token` only
- `resource` (RFC 8707) must equal `Newton.OAuth.canonical_resource()` (the canonical MCP URL); a different value is rejected with `invalid_target`
- OAuth error responses use RFC 6749 JSON (`{"error": "...", "error_description": "..."}`) with correct HTTP statuses
- The authorize endpoint lives inside the **existing** `scope "/" ... pipe_through [:browser, :require_authenticated_user]` block (router line ~107) — only a logged-in admin can approve; consent is a CSRF-protected POST
- No narrating comments; predicate names end in `?`; `mix format` before every commit
- Commit subjects as given per task; the executing session appends its required trailer block

---

### Task 1: Tables, schemas, and client registration

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_oauth_tables.exs` (via `mix ecto.gen.migration create_oauth_tables`)
- Create: `lib/newton/oauth/client.ex`
- Create: `lib/newton/oauth/grant.ex`
- Create: `lib/newton/oauth.ex`
- Test: `test/newton/oauth_test.exs`

**Interfaces:**
- Consumes: nothing (first task)
- Produces:
  - `%Newton.OAuth.Client{}` (fields: `client_id`, `client_secret_hash`, `client_name`, `redirect_uris`, `token_endpoint_auth_method`)
  - `%Newton.OAuth.Grant{}` (fields listed in the migration below)
  - `Newton.OAuth.register_client(map) :: {:ok, {%Client{}, client_secret :: String.t() | nil}} | {:error, Ecto.Changeset.t()}`
  - `Newton.OAuth.get_client(String.t()) :: %Client{} | nil`
  - `Newton.OAuth.authenticate_client(String.t(), String.t() | nil) :: {:ok, %Client{}} | {:error, :invalid_client}`
  - `Newton.OAuth.generate_secret() :: String.t()` and `Newton.OAuth.hash(String.t()) :: binary()` (used by Task 2)

- [ ] **Step 1: Write the failing tests**

Create `test/newton/oauth_test.exs`:

```elixir
defmodule Newton.OAuthTest do
  use Newton.DataCase, async: true

  alias Newton.OAuth

  @valid_registration %{
    "client_name" => "Claude",
    "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
    "token_endpoint_auth_method" => "client_secret_basic"
  }

  describe "register_client/1" do
    test "registers a confidential client and returns the secret exactly once" do
      assert {:ok, {client, secret}} = OAuth.register_client(@valid_registration)

      assert client.client_name == "Claude"
      assert client.redirect_uris == ["https://claude.ai/api/mcp/auth_callback"]
      assert is_binary(client.client_id)
      assert is_binary(secret)
      assert client.client_secret_hash == :crypto.hash(:sha256, secret)
    end

    test "registers a public client without a secret" do
      attrs = Map.put(@valid_registration, "token_endpoint_auth_method", "none")

      assert {:ok, {client, nil}} = OAuth.register_client(attrs)
      assert client.client_secret_hash == nil
    end

    test "defaults token_endpoint_auth_method to client_secret_basic" do
      attrs = Map.delete(@valid_registration, "token_endpoint_auth_method")

      assert {:ok, {client, secret}} = OAuth.register_client(attrs)
      assert client.token_endpoint_auth_method == "client_secret_basic"
      assert is_binary(secret)
    end

    test "rejects non-https redirect uris except loopback http" do
      for bad <- ["http://evil.example/cb", "ftp://x/cb", "not a url", "claude.ai/cb"] do
        attrs = Map.put(@valid_registration, "redirect_uris", [bad])
        assert {:error, changeset} = OAuth.register_client(attrs)
        assert %{redirect_uris: _} = errors_on(changeset)
      end

      for ok <- ["http://127.0.0.1:8976/cb", "http://localhost:33418/cb"] do
        attrs = Map.put(@valid_registration, "redirect_uris", [ok])
        assert {:ok, _} = OAuth.register_client(attrs)
      end
    end

    test "rejects empty redirect uri lists and unknown auth methods" do
      assert {:error, _} = OAuth.register_client(Map.put(@valid_registration, "redirect_uris", []))

      assert {:error, _} =
               OAuth.register_client(
                 Map.put(@valid_registration, "token_endpoint_auth_method", "private_key_jwt")
               )
    end
  end

  describe "authenticate_client/2" do
    test "authenticates a confidential client by secret" do
      {:ok, {client, secret}} = OAuth.register_client(@valid_registration)

      assert {:ok, authed} = OAuth.authenticate_client(client.client_id, secret)
      assert authed.id == client.id
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, "wrong")
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, nil)
    end

    test "authenticates a public client only without a secret" do
      attrs = Map.put(@valid_registration, "token_endpoint_auth_method", "none")
      {:ok, {client, nil}} = OAuth.register_client(attrs)

      assert {:ok, _} = OAuth.authenticate_client(client.client_id, nil)
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, "anything")
    end

    test "unknown client_id fails closed" do
      assert {:error, :invalid_client} = OAuth.authenticate_client("nope", "secret")
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/oauth_test.exs`
Expected: FAIL — `Newton.OAuth` is undefined.

- [ ] **Step 3: Generate and fill the migration**

Run: `mix ecto.gen.migration create_oauth_tables`

```elixir
defmodule Newton.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  def change do
    create table(:oauth_clients) do
      add :client_id, :string, null: false
      add :client_secret_hash, :binary
      add :client_name, :string, null: false
      add :redirect_uris, {:array, :string}, null: false
      add :token_endpoint_auth_method, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_clients, [:client_id])

    create table(:oauth_grants) do
      add :client_id, references(:oauth_clients, on_delete: :delete_all), null: false
      add :code_hash, :binary
      add :code_expires_at, :utc_datetime
      add :code_used_at, :utc_datetime
      add :code_challenge, :string, null: false
      add :redirect_uri, :string, null: false
      add :resource, :string, null: false
      add :access_token_hash, :binary
      add :access_token_expires_at, :utc_datetime
      add :refresh_token_hash, :binary
      add :previous_refresh_token_hash, :binary
      add :refresh_token_expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_grants, [:code_hash])
    create index(:oauth_grants, [:access_token_hash])
    create index(:oauth_grants, [:refresh_token_hash])
    create index(:oauth_grants, [:previous_refresh_token_hash])
    create index(:oauth_grants, [:client_id])
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 4: Create the schemas**

`lib/newton/oauth/client.ex`:

```elixir
defmodule Newton.OAuth.Client do
  use Ecto.Schema
  import Ecto.Changeset

  @auth_methods ~w(none client_secret_post client_secret_basic)

  schema "oauth_clients" do
    field :client_id, :string
    field :client_secret_hash, :binary
    field :client_name, :string
    field :redirect_uris, {:array, :string}
    field :token_endpoint_auth_method, :string, default: "client_secret_basic"

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec registration_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def registration_changeset(client, attrs) do
    client
    |> cast(attrs, [:client_name, :redirect_uris, :token_endpoint_auth_method])
    |> validate_required([:client_name, :redirect_uris])
    |> validate_length(:redirect_uris, min: 1)
    |> validate_inclusion(:token_endpoint_auth_method, @auth_methods)
    |> validate_change(:redirect_uris, &validate_redirect_uris/2)
  end

  defp validate_redirect_uris(:redirect_uris, uris) do
    if Enum.all?(uris, &allowed_redirect_uri?/1),
      do: [],
      else: [redirect_uris: "must be absolute https URLs (or http loopback)"]
  end

  defp allowed_redirect_uri?(uri) do
    case URI.new(uri) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> true
      {:ok, %URI{scheme: "http", host: host}} -> host in ["127.0.0.1", "localhost", "::1"]
      _ -> false
    end
  end
end
```

`lib/newton/oauth/grant.ex`:

```elixir
defmodule Newton.OAuth.Grant do
  use Ecto.Schema

  alias Newton.OAuth.Client

  schema "oauth_grants" do
    belongs_to :client, Client
    field :code_hash, :binary
    field :code_expires_at, :utc_datetime
    field :code_used_at, :utc_datetime
    field :code_challenge, :string
    field :redirect_uri, :string
    field :resource, :string
    field :access_token_hash, :binary
    field :access_token_expires_at, :utc_datetime
    field :refresh_token_hash, :binary
    field :previous_refresh_token_hash, :binary
    field :refresh_token_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
```

- [ ] **Step 5: Create the context with registration and client auth**

`lib/newton/oauth.ex`:

```elixir
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
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/newton/oauth_test.exs`
Expected: all PASS.

- [ ] **Step 7: Format and commit**

```bash
mix format
git add priv/repo/migrations lib/newton/oauth lib/newton/oauth.ex test/newton/oauth_test.exs
git commit -m "Add OAuth client registration and grant storage"
```

---

### Task 2: Grant lifecycle — codes, PKCE exchange, refresh rotation, bearer verification

**Files:**
- Modify: `lib/newton/oauth.ex`
- Modify: `lib/newton/oauth/grant.ex` (no changes expected; listed for the implementer's context)
- Test: `test/newton/oauth_test.exs`

**Interfaces:**
- Consumes: Task 1's `Client`, `Grant`, `generate_secret/0`, `hash/1`, `authenticate_client/2`
- Produces (Tasks 3–5 and plan 2 rely on these exact shapes):
  - `Newton.OAuth.canonical_resource() :: String.t()` — `NewtonWeb.Endpoint.url() <> "/mcp"`
  - `Newton.OAuth.issue_code(%Client{}, String.t(), String.t(), String.t()) :: {:ok, String.t()}` (args: client, redirect_uri, code_challenge, resource)
  - `Newton.OAuth.exchange_code(%Client{}, String.t(), String.t(), String.t()) :: {:ok, token_response} | {:error, :invalid_grant}` (args: client, code, redirect_uri, code_verifier)
  - `Newton.OAuth.refresh(%Client{}, String.t()) :: {:ok, token_response} | {:error, :invalid_grant}`
  - `Newton.OAuth.verify_access_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}` — claims map with `"sub"`, `"aud"`, `"client_id"`
  - `token_response :: %{access_token: String.t(), token_type: "Bearer", expires_in: 3600, refresh_token: String.t()}`

- [ ] **Step 1: Write the failing tests**

Append inside `Newton.OAuthTest` (after the existing describes). Note the helper functions at the bottom go inside the module too:

```elixir
  describe "grant lifecycle" do
    test "full happy path: code -> tokens -> verified bearer" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:ok, tokens} = OAuth.exchange_code(client, code, redirect_uri(), verifier)
      assert %{access_token: at, refresh_token: rt, token_type: "Bearer", expires_in: 3600} = tokens
      assert is_binary(at) and is_binary(rt)

      assert {:ok, claims} = OAuth.verify_access_token(at)
      assert claims["aud"] == OAuth.canonical_resource()
      assert claims["client_id"] == client.client_id
      assert is_binary(claims["sub"])
    end

    test "wrong PKCE verifier is rejected" do
      {client, _} = registered_client()
      {_verifier, challenge} = pkce_pair()
      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, redirect_uri(), "wrong-verifier-wrong-verifier-wrong-verifier")
    end

    test "redirect_uri mismatch at exchange is rejected" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()
      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, "https://claude.ai/other", verifier)
    end

    test "a code from one client cannot be exchanged by another" do
      {client, _} = registered_client()
      {other, _} = registered_client()
      {verifier, challenge} = pkce_pair()
      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} = OAuth.exchange_code(other, code, redirect_uri(), verifier)
    end

    test "an expired code is rejected" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()
      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      expire_code(code)

      assert {:error, :invalid_grant} = OAuth.exchange_code(client, code, redirect_uri(), verifier)
    end

    test "code reuse revokes the whole grant" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()
      {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      {:ok, %{access_token: at}} = OAuth.exchange_code(client, code, redirect_uri(), verifier)
      assert {:error, :invalid_grant} = OAuth.exchange_code(client, code, redirect_uri(), verifier)
      assert {:error, :invalid_token} = OAuth.verify_access_token(at)
    end

    test "refresh rotates both tokens and old access token dies at expiry only" do
      {client, _} = registered_client()
      {:ok, %{access_token: at1, refresh_token: rt1}} = issued_tokens(client)

      assert {:ok, %{access_token: at2, refresh_token: rt2}} = OAuth.refresh(client, rt1)
      assert at2 != at1 and rt2 != rt1
      assert {:ok, _} = OAuth.verify_access_token(at2)
    end

    test "reusing a rotated refresh token revokes the grant" do
      {client, _} = registered_client()
      {:ok, %{refresh_token: rt1}} = issued_tokens(client)
      {:ok, %{access_token: at2, refresh_token: _rt2}} = OAuth.refresh(client, rt1)

      assert {:error, :invalid_grant} = OAuth.refresh(client, rt1)
      assert {:error, :invalid_token} = OAuth.verify_access_token(at2)
    end

    test "a refresh token past its absolute expiry is rejected" do
      {client, _} = registered_client()
      {:ok, %{refresh_token: rt}} = issued_tokens(client)

      expire_refresh(rt)

      assert {:error, :invalid_grant} = OAuth.refresh(client, rt)
    end

    test "an expired access token fails verification" do
      {client, _} = registered_client()
      {:ok, %{access_token: at}} = issued_tokens(client)

      expire_access(at)

      assert {:error, :invalid_token} = OAuth.verify_access_token(at)
    end

    test "garbage bearer values fail closed" do
      assert {:error, :invalid_token} = OAuth.verify_access_token("nonsense")
      assert {:error, :invalid_token} = OAuth.verify_access_token("")
    end
  end

  defp redirect_uri, do: "https://claude.ai/api/mcp/auth_callback"

  defp registered_client do
    {:ok, {client, secret}} = OAuth.register_client(@valid_registration)
    {client, secret}
  end

  defp pkce_pair do
    verifier = OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    {verifier, challenge}
  end

  defp issued_tokens(client) do
    {verifier, challenge} = pkce_pair()
    {:ok, code} = OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())
    OAuth.exchange_code(client, code, redirect_uri(), verifier)
  end

  defp expire_code(code) do
    backdate(:code_hash, code, :code_expires_at)
  end

  defp expire_access(token) do
    backdate(:access_token_hash, token, :access_token_expires_at)
  end

  defp expire_refresh(token) do
    backdate(:refresh_token_hash, token, :refresh_token_expires_at)
  end

  defp backdate(hash_field, secret, expiry_field) do
    import Ecto.Query

    past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

    {1, _} =
      Newton.Repo.update_all(
        from(g in Newton.OAuth.Grant, where: field(g, ^hash_field) == ^OAuth.hash(secret)),
        set: [{expiry_field, past}]
      )
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/oauth_test.exs`
Expected: the new describe FAILs (`issue_code/4` undefined); Task 1 tests still pass.

- [ ] **Step 3: Implement the grant lifecycle**

Append to `lib/newton/oauth.ex` (inside the module; add `alias Newton.OAuth.Grant` beside the existing aliases):

```elixir
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
  def issue_code(%Client{} = client, redirect_uri, code_challenge, resource) do
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
    grant = Repo.get_by(Grant, code_hash: hash(code))

    cond do
      is_nil(grant) or not is_nil(grant.revoked_at) ->
        {:error, :invalid_grant}

      not is_nil(grant.code_used_at) ->
        revoke(grant)
        {:error, :invalid_grant}

      grant.client_id != client.id ->
        {:error, :invalid_grant}

      expired?(grant.code_expires_at) ->
        {:error, :invalid_grant}

      grant.redirect_uri != redirect_uri ->
        {:error, :invalid_grant}

      not pkce_valid?(grant.code_challenge, code_verifier) ->
        {:error, :invalid_grant}

      true ->
        issue_tokens(grant, %{
          code_used_at: now(),
          refresh_token_expires_at: expires_in(@refresh_ttl_seconds)
        })
    end
  end

  def exchange_code(_, _, _, _), do: {:error, :invalid_grant}

  @spec refresh(%Client{}, String.t()) :: {:ok, token_response()} | {:error, :invalid_grant}
  def refresh(%Client{} = client, refresh_token) when is_binary(refresh_token) do
    hashed = hash(refresh_token)

    cond do
      grant = active_grant_by(client, refresh_token_hash: hashed) ->
        if expired?(grant.refresh_token_expires_at),
          do: {:error, :invalid_grant},
          else: issue_tokens(grant, %{})

      grant = active_grant_by(client, previous_refresh_token_hash: hashed) ->
        revoke(grant)
        {:error, :invalid_grant}

      true ->
        {:error, :invalid_grant}
    end
  end

  def refresh(_, _), do: {:error, :invalid_grant}

  @spec verify_access_token(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def verify_access_token(token) when is_binary(token) and token != "" do
    grant =
      Repo.one(
        from g in Grant,
          where: g.access_token_hash == ^hash(token) and is_nil(g.revoked_at),
          preload: [:client]
      )

    if grant && not expired?(grant.access_token_expires_at) do
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
    Repo.get_by(Grant, [{:client_id, client_id}, {:revoked_at, nil} | clause])
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
```

Note: `Repo.get_by/2` with `revoked_at: nil` compiles to `IS NULL` — valid Ecto.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/oauth_test.exs`
Expected: all PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/newton/oauth.ex test/newton/oauth_test.exs
git commit -m "Add OAuth grant lifecycle with PKCE and rotation"
```

---

### Task 3: Discovery metadata and dynamic client registration endpoints

**Files:**
- Create: `lib/newton_web/controllers/oauth_controller.ex`
- Modify: `lib/newton_web/router.ex` (add one scope; exact block below)
- Test: `test/newton_web/controllers/oauth_controller_test.exs`

**Interfaces:**
- Consumes: `Newton.OAuth.register_client/1` (Task 1)
- Produces: routes `GET /.well-known/oauth-authorization-server`, `POST /oauth/register`; the `NewtonWeb.OAuthController` module that Task 5 adds a `token/2` action to

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/controllers/oauth_controller_test.exs`:

```elixir
defmodule NewtonWeb.OAuthControllerTest do
  use NewtonWeb.ConnCase, async: true

  describe "GET /.well-known/oauth-authorization-server" do
    test "returns RFC 8414 metadata", %{conn: conn} do
      body = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      base = NewtonWeb.Endpoint.url()
      assert body["issuer"] == base
      assert body["authorization_endpoint"] == base <> "/oauth/authorize"
      assert body["token_endpoint"] == base <> "/oauth/token"
      assert body["registration_endpoint"] == base <> "/oauth/register"
      assert body["grant_types_supported"] == ["authorization_code", "refresh_token"]
      assert body["response_types_supported"] == ["code"]
      assert body["code_challenge_methods_supported"] == ["S256"]

      assert body["token_endpoint_auth_methods_supported"] ==
               ["none", "client_secret_post", "client_secret_basic"]
    end
  end

  describe "POST /oauth/register" do
    test "registers a client and returns credentials once", %{conn: conn} do
      body =
        conn
        |> post("/oauth/register", %{
          "client_name" => "Claude",
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => "client_secret_basic"
        })
        |> json_response(201)

      assert is_binary(body["client_id"])
      assert is_binary(body["client_secret"])
      assert body["client_name"] == "Claude"
      assert body["redirect_uris"] == ["https://claude.ai/api/mcp/auth_callback"]
      assert body["token_endpoint_auth_method"] == "client_secret_basic"
    end

    test "public clients get no client_secret key", %{conn: conn} do
      body =
        conn
        |> post("/oauth/register", %{
          "client_name" => "CLI",
          "redirect_uris" => ["http://127.0.0.1:8976/cb"],
          "token_endpoint_auth_method" => "none"
        })
        |> json_response(201)

      refute Map.has_key?(body, "client_secret")
    end

    test "invalid registration returns RFC 7591 error", %{conn: conn} do
      body =
        conn
        |> post("/oauth/register", %{
          "client_name" => "Bad",
          "redirect_uris" => ["http://evil.example/cb"]
        })
        |> json_response(400)

      assert body["error"] == "invalid_client_metadata"
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/controllers/oauth_controller_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Create the controller**

`lib/newton_web/controllers/oauth_controller.ex`:

```elixir
defmodule NewtonWeb.OAuthController do
  use NewtonWeb, :controller

  alias Newton.OAuth

  def authorization_server_metadata(conn, _params) do
    base = NewtonWeb.Endpoint.url()

    json(conn, %{
      issuer: base,
      authorization_endpoint: base <> "/oauth/authorize",
      token_endpoint: base <> "/oauth/token",
      registration_endpoint: base <> "/oauth/register",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"]
    })
  end

  def register(conn, params) do
    case OAuth.register_client(params) do
      {:ok, {client, secret}} ->
        response = %{
          client_id: client.client_id,
          client_name: client.client_name,
          redirect_uris: client.redirect_uris,
          token_endpoint_auth_method: client.token_endpoint_auth_method
        }

        response = if secret, do: Map.put(response, :client_secret, secret), else: response

        conn |> put_status(201) |> json(response)

      {:error, _changeset} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_client_metadata", error_description: "invalid registration"})
    end
  end
end
```

- [ ] **Step 4: Add the routes**

In `lib/newton_web/router.ex`, after the existing `scope "/", NewtonWeb do pipe_through :machine_readable ... end` block (around line 70), add:

```elixir
  scope "/", NewtonWeb do
    pipe_through :api

    get "/.well-known/oauth-authorization-server", OAuthController, :authorization_server_metadata
    post "/oauth/register", OAuthController, :register
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton_web/controllers/oauth_controller_test.exs`
Expected: all PASS.

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/newton_web/controllers/oauth_controller.ex lib/newton_web/router.ex test/newton_web/controllers/oauth_controller_test.exs
git commit -m "Serve OAuth discovery metadata and dynamic registration"
```

---

### Task 4: Authorize endpoint and consent page (admin-gated)

**Files:**
- Create: `lib/newton_web/controllers/oauth_authorization_controller.ex`
- Create: `lib/newton_web/controllers/oauth_authorization_html.ex`
- Create: `lib/newton_web/controllers/oauth_authorization_html/consent.html.heex`
- Create: `lib/newton_web/controllers/oauth_authorization_html/error.html.heex`
- Modify: `lib/newton_web/router.ex` (two routes inside the **existing** authenticated scope)
- Test: `test/newton_web/controllers/oauth_authorization_controller_test.exs`

**Interfaces:**
- Consumes: `OAuth.get_client/1`, `OAuth.issue_code/4`, `OAuth.canonical_resource/0`
- Produces: `GET/POST /oauth/authorize` behind admin login; nothing module-level for later tasks

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/controllers/oauth_authorization_controller_test.exs`:

```elixir
defmodule NewtonWeb.OAuthAuthorizationControllerTest do
  use NewtonWeb.ConnCase, async: true

  import Newton.AccountsFixtures

  alias Newton.OAuth

  setup %{conn: conn} do
    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
        "token_endpoint_auth_method" => "client_secret_basic"
      })

    %{conn: log_in_user(conn, user_fixture()), client: client}
  end

  defp challenge do
    Base.url_encode64(:crypto.hash(:sha256, "test-verifier-test-verifier-test-verifier"), padding: false)
  end

  defp authorize_params(client, overrides \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => client.client_id,
        "redirect_uri" => "https://claude.ai/api/mcp/auth_callback",
        "state" => "xyz",
        "code_challenge" => challenge(),
        "code_challenge_method" => "S256",
        "resource" => OAuth.canonical_resource()
      },
      overrides
    )
  end

  test "unauthenticated authorize redirects to login" do
    conn = build_conn()
    conn = get(conn, ~p"/oauth/authorize")
    assert redirected_to(conn) == ~p"/login"
  end

  test "renders consent for a valid request", %{conn: conn, client: client} do
    conn = get(conn, ~p"/oauth/authorize?#{authorize_params(client)}")
    html = html_response(conn, 200)

    assert html =~ "Claude"
    assert html =~ "claude.ai"
    assert has_element_id?(html, "oauth-consent-form")
  end

  defp has_element_id?(html, id), do: html =~ ~s(id="#{id}")

  test "approval issues a code and redirects with state", %{conn: conn, client: client} do
    conn = post(conn, ~p"/oauth/authorize", Map.put(authorize_params(client), "decision", "approve"))

    location = redirected_to(conn)
    uri = URI.parse(location)
    query = URI.decode_query(uri.query)

    assert location =~ "https://claude.ai/api/mcp/auth_callback"
    assert query["state"] == "xyz"
    assert is_binary(query["code"]) and byte_size(query["code"]) > 20
  end

  test "denial redirects with access_denied", %{conn: conn, client: client} do
    conn = post(conn, ~p"/oauth/authorize", Map.put(authorize_params(client), "decision", "deny"))

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["error"] == "access_denied"
    assert query["state"] == "xyz"
  end

  test "unregistered redirect_uri renders an error page and never redirects",
       %{conn: conn, client: client} do
    params = authorize_params(client, %{"redirect_uri" => "https://evil.example/cb"})
    conn = get(conn, ~p"/oauth/authorize?#{params}")

    assert html_response(conn, 400) =~ "redirect"
  end

  test "unknown client renders an error page", %{conn: conn, client: client} do
    params = authorize_params(client, %{"client_id" => "nope"})
    conn = get(conn, ~p"/oauth/authorize?#{params}")

    assert html_response(conn, 400) =~ "client"
  end

  test "missing or plain code_challenge redirects back with invalid_request",
       %{conn: conn, client: client} do
    for overrides <- [%{"code_challenge" => nil}, %{"code_challenge_method" => "plain"}] do
      params = authorize_params(client, overrides)
      conn = get(conn, ~p"/oauth/authorize?#{params}")

      query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert query["error"] == "invalid_request"
      assert query["state"] == "xyz"
    end
  end

  test "wrong response_type redirects back with unsupported_response_type",
       %{conn: conn, client: client} do
    params = authorize_params(client, %{"response_type" => "token"})
    conn = get(conn, ~p"/oauth/authorize?#{params}")

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["error"] == "unsupported_response_type"
  end

  test "wrong resource redirects back with invalid_target", %{conn: conn, client: client} do
    params = authorize_params(client, %{"resource" => "https://other.example/mcp"})
    conn = get(conn, ~p"/oauth/authorize?#{params}")

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["error"] == "invalid_target"
  end

  test "omitted resource defaults to the canonical MCP URL", %{conn: conn, client: client} do
    params = Map.delete(authorize_params(client), "resource")
    conn = post(conn, ~p"/oauth/authorize", Map.put(params, "decision", "approve"))

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert is_binary(query["code"])
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/controllers/oauth_authorization_controller_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Create the controller**

`lib/newton_web/controllers/oauth_authorization_controller.ex`:

```elixir
defmodule NewtonWeb.OAuthAuthorizationController do
  use NewtonWeb, :controller

  alias Newton.OAuth

  def authorize(conn, params) do
    with {:ok, client, redirect_uri} <- fetch_client_and_redirect(params),
         :ok <- validate_request(params) do
      render(conn, :consent,
        client: client,
        redirect_uri: redirect_uri,
        params: consent_params(params),
        page_title: "Authorize #{client.client_name}"
      )
    else
      {:render_error, message} ->
        conn |> put_status(400) |> render(:error, message: message, page_title: "Authorization error")

      {:redirect_error, error} ->
        redirect_with_error(conn, params, error)
    end
  end

  def approve(conn, %{"decision" => "approve"} = params) do
    with {:ok, client, redirect_uri} <- fetch_client_and_redirect(params),
         :ok <- validate_request(params) do
      {:ok, code} =
        OAuth.issue_code(client, redirect_uri, params["code_challenge"], resource(params))

      redirect_back(conn, redirect_uri, %{"code" => code, "state" => params["state"]})
    else
      {:render_error, message} ->
        conn |> put_status(400) |> render(:error, message: message, page_title: "Authorization error")

      {:redirect_error, error} ->
        redirect_with_error(conn, params, error)
    end
  end

  def approve(conn, params) do
    case fetch_client_and_redirect(params) do
      {:ok, _client, redirect_uri} ->
        redirect_back(conn, redirect_uri, %{"error" => "access_denied", "state" => params["state"]})

      {:render_error, message} ->
        conn |> put_status(400) |> render(:error, message: message, page_title: "Authorization error")
    end
  end

  defp fetch_client_and_redirect(params) do
    client = OAuth.get_client(params["client_id"])

    cond do
      is_nil(client) ->
        {:render_error, "Unknown client. Check the client_id and register the client first."}

      params["redirect_uri"] not in client.redirect_uris ->
        {:render_error, "The redirect address is not registered for this client."}

      true ->
        {:ok, client, params["redirect_uri"]}
    end
  end

  defp validate_request(params) do
    cond do
      params["response_type"] != "code" -> {:redirect_error, "unsupported_response_type"}
      not is_binary(params["code_challenge"]) -> {:redirect_error, "invalid_request"}
      params["code_challenge"] == "" -> {:redirect_error, "invalid_request"}
      params["code_challenge_method"] != "S256" -> {:redirect_error, "invalid_request"}
      resource(params) != OAuth.canonical_resource() -> {:redirect_error, "invalid_target"}
      true -> :ok
    end
  end

  defp resource(params), do: params["resource"] || OAuth.canonical_resource()

  defp redirect_with_error(conn, params, error) do
    redirect_back(conn, params["redirect_uri"], %{"error" => error, "state" => params["state"]})
  end

  defp redirect_back(conn, redirect_uri, query) do
    query = query |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> URI.encode_query()
    redirect(conn, external: redirect_uri <> "?" <> query)
  end

  defp consent_params(params) do
    Map.take(params, ~w(response_type client_id redirect_uri state code_challenge code_challenge_method resource))
  end
end
```

- [ ] **Step 4: Create the HTML module and templates**

`lib/newton_web/controllers/oauth_authorization_html.ex`:

```elixir
defmodule NewtonWeb.OAuthAuthorizationHTML do
  use NewtonWeb, :html

  embed_templates "oauth_authorization_html/*"
end
```

`lib/newton_web/controllers/oauth_authorization_html/consent.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Authorize {@client.client_name}</h1>
    </header>

    <p>
      <strong>{@client.client_name}</strong>
      wants read access to your posts, drafts included. Approving sends it back to
      <strong>{URI.parse(@redirect_uri).host}</strong>.
    </p>

    <form method="post" action={~p"/oauth/authorize"} id="oauth-consent-form">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input :for={{name, value} <- @params} type="hidden" name={name} value={value} />
      <button type="submit" name="decision" value="approve">Approve</button>
      <button type="submit" name="decision" value="deny">Deny</button>
    </form>
  </article>
</Layouts.app>
```

`lib/newton_web/controllers/oauth_authorization_html/error.html.heex`:

```heex
<Layouts.app flash={@flash}>
  <article class="post">
    <header>
      <h1 class="post-title">Authorization error</h1>
    </header>

    <p>{@message}</p>
  </article>
</Layouts.app>
```

- [ ] **Step 5: Add the routes inside the existing authenticated scope**

In `lib/newton_web/router.ex`, find the **existing** block (~line 107):

```elixir
  scope "/", NewtonWeb do
    pipe_through [:browser, :require_authenticated_user]
```

and add inside it:

```elixir
    get "/oauth/authorize", OAuthAuthorizationController, :authorize
    post "/oauth/authorize", OAuthAuthorizationController, :approve
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/newton_web/controllers/oauth_authorization_controller_test.exs`
Expected: all PASS. If `redirected_to/1` fails on the login redirect test because the login path differs, check `lib/newton_web/user_auth.ex` for the actual path and update the assertion — do not change the router.

- [ ] **Step 7: Format and commit**

```bash
mix format
git add lib/newton_web/controllers/oauth_authorization_controller.ex lib/newton_web/controllers/oauth_authorization_html.ex lib/newton_web/controllers/oauth_authorization_html lib/newton_web/router.ex test/newton_web/controllers/oauth_authorization_controller_test.exs
git commit -m "Add the admin-gated OAuth authorize and consent flow"
```

---

### Task 5: Token endpoint

**Files:**
- Modify: `lib/newton_web/controllers/oauth_controller.ex` (add `token/2` + helpers)
- Modify: `lib/newton_web/router.ex` (one route in the Task 3 scope)
- Test: `test/newton_web/controllers/oauth_controller_test.exs`

**Interfaces:**
- Consumes: `OAuth.authenticate_client/2`, `OAuth.exchange_code/4`, `OAuth.refresh/2` (Tasks 1–2)
- Produces: `POST /oauth/token` — the last piece plan 2's end-to-end flow needs

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/controllers/oauth_controller_test.exs` (inside the module):

```elixir
  describe "POST /oauth/token" do
    alias Newton.OAuth

    defp register!(method) do
      {:ok, {client, secret}} =
        OAuth.register_client(%{
          "client_name" => "Claude",
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => method
        })

      {client, secret}
    end

    defp pkce do
      verifier = OAuth.generate_secret()
      {verifier, Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)}
    end

    defp code_for(client, challenge) do
      {:ok, code} =
        OAuth.issue_code(
          client,
          "https://claude.ai/api/mcp/auth_callback",
          challenge,
          OAuth.canonical_resource()
        )

      code
    end

    defp exchange_params(client, code, verifier) do
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => "https://claude.ai/api/mcp/auth_callback",
        "code_verifier" => verifier,
        "client_id" => client.client_id
      }
    end

    test "exchanges a code with client_secret_basic auth", %{conn: conn} do
      {client, secret} = register!("client_secret_basic")
      {verifier, challenge} = pkce()
      code = code_for(client, challenge)

      body =
        conn
        |> put_req_header(
          "authorization",
          "Basic " <> Base.encode64(client.client_id <> ":" <> secret)
        )
        |> post(~p"/oauth/token", exchange_params(client, code, verifier))
        |> json_response(200)

      assert %{
               "access_token" => _,
               "refresh_token" => _,
               "token_type" => "Bearer",
               "expires_in" => 3600
             } = body
    end

    test "exchanges a code with client_secret_post auth", %{conn: conn} do
      {client, secret} = register!("client_secret_post")
      {verifier, challenge} = pkce()
      code = code_for(client, challenge)

      params = Map.put(exchange_params(client, code, verifier), "client_secret", secret)
      assert %{"access_token" => _} = conn |> post(~p"/oauth/token", params) |> json_response(200)
    end

    test "exchanges a code for a public client with PKCE only", %{conn: conn} do
      {client, nil} = register!("none")
      {verifier, challenge} = pkce()
      code = code_for(client, challenge)

      assert %{"access_token" => _} =
               conn
               |> post(~p"/oauth/token", exchange_params(client, code, verifier))
               |> json_response(200)
    end

    test "wrong client secret returns 401 invalid_client", %{conn: conn} do
      {client, _secret} = register!("client_secret_basic")
      {verifier, challenge} = pkce()
      code = code_for(client, challenge)

      body =
        conn
        |> put_req_header(
          "authorization",
          "Basic " <> Base.encode64(client.client_id <> ":wrong")
        )
        |> post(~p"/oauth/token", exchange_params(client, code, verifier))
        |> json_response(401)

      assert body["error"] == "invalid_client"
    end

    test "wrong verifier returns invalid_grant", %{conn: conn} do
      {client, nil} = register!("none")
      {_verifier, challenge} = pkce()
      code = code_for(client, challenge)

      body =
        conn
        |> post(~p"/oauth/token", exchange_params(client, code, "wrong-verifier-wrong-verifier"))
        |> json_response(400)

      assert body["error"] == "invalid_grant"
    end

    test "refresh_token grant rotates tokens", %{conn: conn} do
      {client, nil} = register!("none")
      {verifier, challenge} = pkce()
      code = code_for(client, challenge)

      %{"refresh_token" => rt} =
        conn |> post(~p"/oauth/token", exchange_params(client, code, verifier)) |> json_response(200)

      body =
        conn
        |> post(~p"/oauth/token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => rt,
          "client_id" => client.client_id
        })
        |> json_response(200)

      assert body["refresh_token"] != rt
      assert is_binary(body["access_token"])
    end

    test "unsupported grant types are rejected", %{conn: conn} do
      body =
        conn
        |> post(~p"/oauth/token", %{"grant_type" => "password", "username" => "x"})
        |> json_response(400)

      assert body["error"] == "unsupported_grant_type"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/controllers/oauth_controller_test.exs`
Expected: new tests FAIL — no `/oauth/token` route. Task 3 tests still pass.

- [ ] **Step 3: Add the token action**

Append to `NewtonWeb.OAuthController` (before the final `end`):

```elixir
  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    with {:ok, client} <- authenticated_client(conn, params),
         {:ok, tokens} <-
           OAuth.exchange_code(client, params["code"], params["redirect_uri"], params["code_verifier"]) do
      json(conn, tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    with {:ok, client} <- authenticated_client(conn, params),
         {:ok, tokens} <- OAuth.refresh(client, params["refresh_token"]) do
      json(conn, tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "unsupported_grant_type", error_description: "use authorization_code or refresh_token"})
  end

  defp authenticated_client(conn, params) do
    {client_id, secret} =
      case Plug.BasicAuth.parse_basic_auth(conn) do
        {basic_id, basic_secret} -> {basic_id, basic_secret}
        :error -> {params["client_id"], params["client_secret"]}
      end

    OAuth.authenticate_client(client_id, secret)
  end

  defp token_error(conn, {:error, :invalid_client}) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"oauth\"")
    |> put_status(401)
    |> json(%{error: "invalid_client", error_description: "client authentication failed"})
  end

  defp token_error(conn, {:error, :invalid_grant}) do
    conn
    |> put_status(400)
    |> json(%{error: "invalid_grant", error_description: "the grant is invalid, expired, or revoked"})
  end
```

- [ ] **Step 4: Add the route**

In the scope added in Task 3, after the register route:

```elixir
    post "/oauth/token", OAuthController, :token
```

- [ ] **Step 5: Run the tests, then the full suite**

Run: `mix test test/newton_web/controllers/oauth_controller_test.exs`
Expected: all PASS.

Run: `mix precommit`
Expected: clean.

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/newton_web/controllers/oauth_controller.ex lib/newton_web/router.ex test/newton_web/controllers/oauth_controller_test.exs
git commit -m "Add the OAuth token endpoint"
```
