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
      for bad <- [
            "http://evil.example/cb",
            "ftp://x/cb",
            "not a url",
            "claude.ai/cb",
            "https://claude.ai/cb#fragment",
            "https://user@evil.example/cb"
          ] do
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
      assert {:error, _} =
               OAuth.register_client(Map.put(@valid_registration, "redirect_uris", []))

      assert {:error, _} =
               OAuth.register_client(
                 Map.put(@valid_registration, "token_endpoint_auth_method", "private_key_jwt")
               )
    end

    test "rejects an overlong client name" do
      attrs = Map.put(@valid_registration, "client_name", String.duplicate("a", 121))

      assert {:error, changeset} = OAuth.register_client(attrs)
      assert %{client_name: _} = errors_on(changeset)
    end

    test "rejects more than five redirect uris" do
      uris = for n <- 1..6, do: "https://claude.ai/cb#{n}"
      attrs = Map.put(@valid_registration, "redirect_uris", uris)

      assert {:error, changeset} = OAuth.register_client(attrs)
      assert %{redirect_uris: _} = errors_on(changeset)
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

  describe "redirect_uri_registered?/2" do
    test "accepts an ephemeral loopback port that differs from the registered port" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      assert OAuth.redirect_uri_registered?(client, "http://localhost:53786/callback")
    end

    test "rejects a loopback URI with a different path" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://localhost:53786/cb")
    end

    test "rejects a loopback URI with a different host" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://127.0.0.2:53786/callback")
    end

    test "grants no port exception to https redirect uris" do
      {:ok, {client, _secret}} = OAuth.register_client(@valid_registration)

      refute OAuth.redirect_uri_registered?(
               client,
               "https://claude.ai:8443/api/mcp/auth_callback"
             )
    end

    test "still accepts an exact match" do
      {:ok, {client, _secret}} = OAuth.register_client(@valid_registration)

      assert OAuth.redirect_uri_registered?(client, "https://claude.ai/api/mcp/auth_callback")
    end

    test "rejects garbage or nil presented uris" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "not a url")
      refute OAuth.redirect_uri_registered?(client, nil)
    end

    test "rejects a presented uri carrying userinfo" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://x@localhost:53786/callback")
    end

    test "rejects a presented uri carrying a fragment" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://localhost:53786/callback#frag")
    end

    test "rejects a lookalike host that merely has localhost as a subdomain label" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://localhost.evil.com:53786/callback")
    end

    test "rejects a lookalike host that merely has 127.0.0.1 as a subdomain label" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://127.0.0.1:3118/callback"])
        )

      refute OAuth.redirect_uri_registered?(client, "http://127.0.0.1.evil.com:53786/callback")
    end
  end

  describe "grant lifecycle" do
    test "full happy path: code -> tokens -> verified bearer" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:ok, tokens} = OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert %{access_token: at, refresh_token: rt, token_type: "Bearer", expires_in: 3600} =
               tokens

      assert is_binary(at) and is_binary(rt)

      assert {:ok, claims} = OAuth.verify_access_token(at)
      assert claims["aud"] == OAuth.canonical_resource()
      assert claims["client_id"] == client.client_id
      assert is_binary(claims["sub"])
    end

    test "wrong PKCE verifier is rejected" do
      {client, _} = registered_client()
      {_verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(
                 client,
                 code,
                 redirect_uri(),
                 "wrong-verifier-wrong-verifier-wrong-verifier"
               )
    end

    test "issue_code accepts a loopback redirect_uri on an unregistered ephemeral port" do
      {:ok, {client, _secret}} =
        OAuth.register_client(
          Map.put(@valid_registration, "redirect_uris", ["http://localhost:3118/callback"])
        )

      {_verifier, challenge} = pkce_pair()

      assert {:ok, _code} =
               OAuth.issue_code(
                 client,
                 "http://localhost:53786/callback",
                 challenge,
                 OAuth.canonical_resource()
               )
    end

    test "redirect_uri mismatch at exchange is rejected" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, "https://claude.ai/other", verifier)
    end

    test "a code from one client cannot be exchanged by another" do
      {client, _} = registered_client()
      {other, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      assert {:error, :invalid_grant} = OAuth.exchange_code(other, code, redirect_uri(), verifier)
    end

    test "an expired code is rejected" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      expire_code(code)

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, redirect_uri(), verifier)
    end

    test "code reuse revokes the whole grant" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      {:ok, %{access_token: at}} = OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert {:error, :invalid_token} = OAuth.verify_access_token(at)
    end

    test "refresh rotates both tokens and invalidates the previous access token" do
      {client, _} = registered_client()
      {:ok, %{access_token: at1, refresh_token: rt1}} = issued_tokens(client)

      assert {:ok, %{access_token: at2, refresh_token: rt2}} = OAuth.refresh(client, rt1)
      assert at2 != at1 and rt2 != rt1
      assert {:ok, _} = OAuth.verify_access_token(at2)
      assert {:error, :invalid_token} = OAuth.verify_access_token(at1)
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

    test "a token bound to a non-canonical resource fails verification" do
      {client, _} = registered_client()
      {:ok, %{access_token: at}} = issued_tokens(client)

      set_grant_resource(at, "https://other.example/mcp")

      assert {:error, :invalid_token} = OAuth.verify_access_token(at)
    end

    test "code reuse emits a [:newton, :oauth, :grant, :stop] event tagged reused_code" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :oauth, :grant, :stop]])

      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      {:ok, _tokens} = OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert_received {[:newton, :oauth, :grant, :stop], ^ref, %{duration: _},
                       %{operation: :exchange_code, result: :ok}}

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert_received {[:newton, :oauth, :grant, :stop], ^ref, %{duration: _},
                       %{operation: :exchange_code, result: :reused_code}}
    end

    test "refresh token absolute expiry is never extended" do
      {client, _} = registered_client()
      {:ok, %{refresh_token: rt1}} = issued_tokens(client)

      grant = find_grant_by_refresh_token(rt1)
      original_expiry = grant.refresh_token_expires_at

      {:ok, %{refresh_token: _rt2}} = OAuth.refresh(client, rt1)

      grant = find_grant_by_previous_refresh_token(rt1)
      assert grant.refresh_token_expires_at == original_expiry
    end

    test "second code exchange attempt returns invalid_grant without side effects" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      {:ok, %{access_token: at1}} = OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert {:error, :invalid_token} = OAuth.verify_access_token(at1)
    end

    test "second refresh attempt with rotated token returns invalid_grant without side effects" do
      {client, _} = registered_client()
      {:ok, %{refresh_token: rt1}} = issued_tokens(client)

      {:ok, %{access_token: at2, refresh_token: _rt2}} = OAuth.refresh(client, rt1)

      assert {:error, :invalid_grant} = OAuth.refresh(client, rt1)

      assert {:error, :invalid_token} = OAuth.verify_access_token(at2)
    end

    test "already-used code with wrong verifier revokes grant" do
      {client, _} = registered_client()
      {verifier, challenge} = pkce_pair()

      {:ok, code} =
        OAuth.issue_code(client, redirect_uri(), challenge, OAuth.canonical_resource())

      {:ok, %{access_token: at}} = OAuth.exchange_code(client, code, redirect_uri(), verifier)

      assert {:error, :invalid_grant} =
               OAuth.exchange_code(
                 client,
                 code,
                 redirect_uri(),
                 "wrong-verifier-wrong-verifier-wrong-verifier"
               )

      assert {:error, :invalid_token} = OAuth.verify_access_token(at)
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

  defp set_grant_resource(access_token, resource) do
    import Ecto.Query

    {1, _} =
      Newton.Repo.update_all(
        from(g in Newton.OAuth.Grant, where: g.access_token_hash == ^OAuth.hash(access_token)),
        set: [resource: resource]
      )
  end

  defp find_grant_by_refresh_token(token) do
    import Ecto.Query

    Newton.Repo.one(
      from(g in Newton.OAuth.Grant,
        where: g.refresh_token_hash == ^OAuth.hash(token)
      )
    )
  end

  defp find_grant_by_previous_refresh_token(token) do
    import Ecto.Query

    Newton.Repo.one(
      from(g in Newton.OAuth.Grant,
        where: g.previous_refresh_token_hash == ^OAuth.hash(token)
      )
    )
  end

  describe "authorized clients" do
    defp connected_client(name) do
      {:ok, {client, _secret}} =
        OAuth.register_client(%{
          "client_name" => name,
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => "none"
        })

      {client, connect(client)}
    end

    defp connect(client) do
      verifier = OAuth.generate_secret()
      challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

      {:ok, code} =
        OAuth.issue_code(
          client,
          "https://claude.ai/api/mcp/auth_callback",
          challenge,
          OAuth.canonical_resource()
        )

      {:ok, tokens} =
        OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

      tokens
    end

    test "lists clients with active grants and their aggregates" do
      {client, _tokens1} = connected_client("Claude Code")
      _tokens2 = connect(client)

      assert [entry] = OAuth.list_authorized_clients()
      assert entry.client.id == client.id
      assert entry.grant_count == 2
      assert %DateTime{} = entry.first_connected_at
      assert %DateTime{} = entry.last_active_at
      assert DateTime.compare(entry.first_connected_at, entry.last_active_at) != :gt
    end

    test "orders clients by most recent activity first" do
      {older, _} = connected_client("Older")
      {newer, _} = connected_client("Newer")

      bump_last_activity(newer)

      assert [first, second] = OAuth.list_authorized_clients()
      assert first.client.id == newer.id
      assert second.client.id == older.id
    end

    test "excludes clients whose grants are all revoked" do
      {client, _tokens} = connected_client("Revoked app")
      assert OAuth.revoke_client_grants(client) == 1

      assert OAuth.list_authorized_clients() == []
    end

    test "excludes clients whose grants are fully expired" do
      {client, _tokens} = connected_client("Expired app")
      expire_all_tokens(client)

      assert OAuth.list_authorized_clients() == []
    end

    test "revoke kills every active grant and its tokens" do
      {client, tokens1} = connected_client("Doomed app")
      tokens2 = connect(client)

      :telemetry_test.attach_event_handlers(self(), [[:newton, :oauth, :grant, :stop]])

      assert OAuth.revoke_client_grants(client) == 2

      assert {:error, :invalid_token} = OAuth.verify_access_token(tokens1.access_token)
      assert {:error, :invalid_token} = OAuth.verify_access_token(tokens2.access_token)
      assert {:error, :invalid_grant} = OAuth.refresh(client, tokens1.refresh_token)
      assert {:error, :invalid_grant} = OAuth.refresh(client, tokens2.refresh_token)

      assert_receive {[:newton, :oauth, :grant, :stop], _ref, _m,
                      %{operation: :admin_revoke, result: :ok}}
    end

    test "revoking a grantless client returns 0" do
      {:ok, {client, _}} =
        OAuth.register_client(%{
          "client_name" => "Never connected",
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => "none"
        })

      assert OAuth.revoke_client_grants(client) == 0
    end

    defp bump_last_activity(client) do
      import Ecto.Query

      future = DateTime.add(DateTime.utc_now(), 60, :second) |> DateTime.truncate(:second)

      {_, _} =
        Newton.Repo.update_all(
          from(g in Newton.OAuth.Grant, where: g.client_id == ^client.id),
          set: [updated_at: future]
        )
    end

    defp expire_all_tokens(client) do
      import Ecto.Query

      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      {_, _} =
        Newton.Repo.update_all(
          from(g in Newton.OAuth.Grant, where: g.client_id == ^client.id),
          set: [access_token_expires_at: past, refresh_token_expires_at: past]
        )
    end
  end
end
