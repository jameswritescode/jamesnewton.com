defmodule NewtonWeb.MCPAuthTest do
  use NewtonWeb.ConnCase, async: false

  test "unauthenticated /mcp requests get 401 with resource metadata pointer", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> post("/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

    assert conn.status == 401
    assert [www] = get_resp_header(conn, "www-authenticate")
    assert www =~ "Bearer"
    assert www =~ "resource_metadata"
  end

  test "protected resource metadata names the resource and authorization server", %{conn: conn} do
    body = conn |> get("/.well-known/oauth-protected-resource") |> json_response(200)

    assert body["resource"] == Newton.OAuth.canonical_resource()
    assert body["authorization_servers"] == [NewtonWeb.Endpoint.url()]
  end
end
