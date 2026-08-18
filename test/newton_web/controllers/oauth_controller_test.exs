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
        conn
        |> post(~p"/oauth/token", exchange_params(client, code, verifier))
        |> json_response(200)

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
end
