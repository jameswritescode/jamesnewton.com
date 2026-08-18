defmodule NewtonWeb.MCPEndToEndTest do
  use NewtonWeb.ConnCase, async: false

  import Newton.AccountsFixtures

  @redirect "http://127.0.0.1:9999/cb"

  defp parse_jsonrpc(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        decoded

      {:error, _} ->
        body
        |> String.split("\n")
        |> Enum.find_value(fn
          "data: " <> data -> Jason.decode!(data)
          _ -> nil
        end)
    end
  end

  defp mcp_post(conn, token, session_id, payload) do
    conn =
      build_conn()
      |> recycle(conn)
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn = if session_id, do: put_req_header(conn, "mcp-session-id", session_id), else: conn

    post(conn, "/mcp", Jason.encode!(payload))
  end

  test "register -> authorize -> exchange -> call MCP tools", %{conn: conn} do
    {:ok, draft} =
      Newton.Blog.create_post(%{
        title: "Secret draft",
        slug: "secret-draft",
        body_markdown: "agent-readable body"
      })

    registration =
      build_conn()
      |> post("/oauth/register", %{
        "client_name" => "e2e",
        "redirect_uris" => [@redirect],
        "token_endpoint_auth_method" => "none"
      })
      |> json_response(201)

    verifier = Newton.OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    authorize_conn =
      conn
      |> log_in_user(user_fixture())
      |> post(~p"/oauth/authorize", %{
        "decision" => "approve",
        "response_type" => "code",
        "client_id" => registration["client_id"],
        "redirect_uri" => @redirect,
        "state" => "e2e",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256",
        "resource" => Newton.OAuth.canonical_resource()
      })

    %{"code" => code} =
      authorize_conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    %{"access_token" => token} =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => @redirect,
        "code_verifier" => verifier,
        "client_id" => registration["client_id"]
      })
      |> json_response(200)

    init_conn =
      mcp_post(conn, token, nil, %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-03-26",
          capabilities: %{},
          clientInfo: %{name: "e2e", version: "1.0"}
        }
      })

    assert init_conn.status == 200
    assert %{"result" => %{"serverInfo" => _}} = parse_jsonrpc(init_conn.resp_body)
    [session_id] = get_resp_header(init_conn, "mcp-session-id")

    mcp_post(conn, token, session_id, %{jsonrpc: "2.0", method: "notifications/initialized"})

    call_conn =
      mcp_post(conn, token, session_id, %{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: %{name: "read_post", arguments: %{slug: draft.slug}}
      })

    assert call_conn.status == 200
    assert %{"result" => result} = parse_jsonrpc(call_conn.resp_body)
    refute result["isError"]
    assert [%{"type" => "text", "text" => text}] = result["content"]
    assert text =~ "agent-readable body"
  end
end
