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
