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
    Base.url_encode64(:crypto.hash(:sha256, "test-verifier-test-verifier-test-verifier"),
      padding: false
    )
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
    conn =
      post(conn, ~p"/oauth/authorize", Map.put(authorize_params(client), "decision", "approve"))

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

  test "a redirect_uri with an existing query string keeps its params alongside the issued code",
       %{conn: conn} do
    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => "Multi-tenant client",
        "redirect_uris" => ["http://127.0.0.1:9000/cb?tenant=1"],
        "token_endpoint_auth_method" => "none"
      })

    params =
      authorize_params(client, %{
        "redirect_uri" => "http://127.0.0.1:9000/cb?tenant=1",
        "decision" => "approve"
      })

    conn = post(conn, ~p"/oauth/authorize", params)

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["tenant"] == "1"
    assert query["state"] == "xyz"
    assert is_binary(query["code"])
  end

  test "approval with a non-S256 code_challenge_method redirects back with invalid_request and no code",
       %{conn: conn, client: client} do
    params =
      authorize_params(client, %{"code_challenge_method" => "plain", "decision" => "approve"})

    conn = post(conn, ~p"/oauth/authorize", params)

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["error"] == "invalid_request"
    assert query["state"] == "xyz"
    refute Map.has_key?(query, "code")
  end

  test "approval with an unregistered redirect_uri renders an error page and never redirects",
       %{conn: conn, client: client} do
    params =
      authorize_params(client, %{
        "redirect_uri" => "https://evil.example/cb",
        "decision" => "approve"
      })

    conn = post(conn, ~p"/oauth/authorize", params)

    assert html_response(conn, 400) =~ "redirect"
  end

  test "the rendered consent form's hidden fields round-trip into a working approval",
       %{conn: conn, client: client} do
    params = authorize_params(client)
    html = conn |> get(~p"/oauth/authorize?#{params}") |> html_response(200)

    hidden_fields =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#oauth-consent-form input[type=hidden]")
      |> LazyHTML.attributes()
      |> Map.new(fn attrs ->
        attrs = Map.new(attrs)
        {attrs["name"], attrs["value"]}
      end)

    assert hidden_fields["code_challenge"] == params["code_challenge"]

    conn = post(conn, ~p"/oauth/authorize", Map.put(hidden_fields, "decision", "approve"))

    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert is_binary(query["code"])
    assert query["state"] == "xyz"
  end
end
