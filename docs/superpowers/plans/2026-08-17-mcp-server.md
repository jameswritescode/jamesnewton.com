# MCP Server Implementation Plan (2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An MCP endpoint at `/mcp` (anubis_mcp, streamable HTTP) guarded by the plan-1 OAuth server, exposing read-only `list_posts` and `read_post` tools that include drafts.

**Architecture:** `Newton.MCP.Server` (`use Anubis.Server`) registers two tool components that call `Newton.Blog`; `Newton.MCP.TokenValidator` implements `Anubis.Server.Authorization.Validator` on top of `Newton.OAuth.verify_access_token/1`. Anubis's transport handles RFC 9728 metadata, bearer extraction, and 401 + `WWW-Authenticate` itself.

**Tech Stack:** `anubis_mcp ~> 2.0` (the maintained fork of hermes_mcp; hermes upstream is deleted and frozen at 0.14.1), Phoenix 1.8.

**Prerequisite:** Plan 1 (`2026-08-17-oauth-authorization-server.md`) is fully implemented — this plan consumes `Newton.OAuth.verify_access_token/1`, `canonical_resource/0`, and the OAuth endpoints.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-17-mcp-server-oauth-design.md`
- Tools are **read-only**; drafts are included by design
- `list_posts(status: "all" | "draft" | "published", default "all")` returns rows of slug, title, status, updated_at; `read_post(slug)` returns title, status, excerpt, markdown body
- Unknown slug → MCP tool error ("no post with slug …"), never a raise
- Telemetry: `[:newton, :mcp, :tool_call]` span via the `Newton.Telemetry.span/4` facade; metadata bounded to `tool` and `result` (atoms/short strings only); metric declared once in `Newton.Metrics.definitions/0` as a `distribution` with explicit buckets — never `summary`
- Every token check goes through `Newton.OAuth.verify_access_token/1` plus an audience check against `Newton.OAuth.canonical_resource()`
- `/mcp` and `/.well-known/oauth-protected-resource` are forwarded in a router scope with **no pipeline** (anubis handles content negotiation and auth; browser plugs would break SSE and CSRF-reject POSTs)
- No narrating comments; predicate names end in `?`; `mix format` before every commit
- Commit subjects as given per task; the executing session appends its required trailer block

---

### Task 1: anubis dependency, Blog slug lookup, and the two tool components

**Files:**
- Modify: `mix.exs` (add `{:anubis_mcp, "~> 2.0"}` to deps)
- Modify: `lib/newton/blog.ex` (add `get_post_by_slug/1` beside `get_post_by_slug!/1`, ~line 78)
- Create: `lib/newton/mcp/tools/list_posts.ex`
- Create: `lib/newton/mcp/tools/read_post.ex`
- Modify: `lib/newton/metrics.ex` (one new distribution in `definitions/0`)
- Test: `test/newton/mcp/tools_test.exs`
- Test: `test/newton/blog_test.exs` (one appended test)

**Interfaces:**
- Consumes: `Newton.Blog.list_posts(:all | :drafts | :published)`, `Newton.Telemetry.span/4`
- Produces:
  - `Newton.Blog.get_post_by_slug(String.t()) :: %Post{} | nil`
  - `Newton.MCP.Tools.ListPosts` and `Newton.MCP.Tools.ReadPost` — anubis tool components with `execute/2`; Task 2's server registers them by these exact names
  - Telemetry event `[:newton, :mcp, :tool_call, :stop]` with measurements + metadata `%{tool: String.t(), result: :ok | :not_found}`

- [ ] **Step 1: Add the dependency**

In `mix.exs` deps, add:

```elixir
      {:anubis_mcp, "~> 2.0"},
```

Run: `mix deps.get`
Expected: resolves anubis_mcp 2.0.x.

- [ ] **Step 2: Write the failing tests**

Append to `test/newton/blog_test.exs` (inside the module):

```elixir
  test "get_post_by_slug/1 returns drafts and nil for unknown slugs" do
    {:ok, post} =
      Blog.create_post(%{title: "Draft post", slug: "draft-post", body_markdown: "hello"})

    assert Blog.get_post_by_slug(post.slug).id == post.id
    assert Blog.get_post_by_slug("no-such-slug") == nil
  end
```

(If `blog_test.exs` builds posts through a fixture or different creation call, follow the file's existing pattern for creating a draft — the assertion pair is what matters.)

Create `test/newton/mcp/tools_test.exs`:

```elixir
defmodule Newton.MCP.ToolsTest do
  use Newton.DataCase, async: true

  alias Anubis.Server.{Frame, Response}
  alias Newton.MCP.Tools.{ListPosts, ReadPost}

  defp create_draft!(title, body) do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: title,
        slug: Newton.Slug.slugify(title),
        body_markdown: body
      })

    post
  end

  defp decoded_json(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  describe "list_posts" do
    test "includes drafts with status all" do
      post = create_draft!("My draft", "body")

      assert {:reply, %Response{isError: false} = response, %Frame{}} =
               ListPosts.execute(%{status: "all"}, %Frame{})

      rows = decoded_json(response)
      assert Enum.any?(rows, &(&1["slug"] == post.slug and &1["status"] == "draft"))
      assert Enum.all?(rows, &(Map.keys(&1) |> Enum.sort() == ~w(slug status title updated_at)))
    end

    test "status filter narrows to drafts" do
      create_draft!("Draft only", "body")

      assert {:reply, response, _} = ListPosts.execute(%{status: "published"}, %Frame{})
      assert decoded_json(response) |> Enum.filter(&(&1["status"] == "draft")) == []

      assert {:reply, response, _} = ListPosts.execute(%{status: "draft"}, %Frame{})
      assert decoded_json(response) |> Enum.all?(&(&1["status"] == "draft"))
    end

    test "schema exposes the status enum with default all" do
      schema = ListPosts.input_schema()
      assert schema["properties"]["status"]["enum"] == ["all", "draft", "published"]
    end
  end

  describe "read_post" do
    test "returns a draft's markdown body" do
      post = create_draft!("Readable draft", "# Heading\n\nSecret draft body")

      assert {:reply, %Response{isError: false} = response, %Frame{}} =
               ReadPost.execute(%{slug: post.slug}, %Frame{})

      body = decoded_json(response)
      assert body["title"] == "Readable draft"
      assert body["status"] == "draft"
      assert body["body_markdown"] =~ "Secret draft body"
    end

    test "unknown slug returns a tool error, not a raise" do
      assert {:reply, %Response{isError: true} = response, %Frame{}} =
               ReadPost.execute(%{slug: "missing"}, %Frame{})

      assert [%{"type" => "text", "text" => text}] = response.content
      assert text =~ "no post with slug"
    end

    test "tool calls emit the telemetry stop event" do
      :telemetry_test.attach_event_handlers(self(), [[:newton, :mcp, :tool_call, :stop]])
      create_draft!("Telemetered", "body")

      ListPosts.execute(%{status: "all"}, %Frame{})

      assert_receive {[:newton, :mcp, :tool_call, :stop], _ref, _measurements, metadata}
      assert metadata.tool == "list_posts"
      assert metadata.result == :ok
    end
  end
end
```

(As with the blog test: if `Blog.create_post/1` has a different arity/required fields, mirror how `blog_test.exs` creates draft posts.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `mix test test/newton/mcp/tools_test.exs test/newton/blog_test.exs`
Expected: FAIL — tool modules and `get_post_by_slug/1` undefined.

- [ ] **Step 4: Add the Blog lookup**

In `lib/newton/blog.ex`, directly after `get_post_by_slug!/1`:

```elixir
  @doc "Fetch any post by slug (drafts included), nil when absent."
  @spec get_post_by_slug(String.t()) :: %Post{} | nil
  def get_post_by_slug(slug), do: Repo.get_by(Post, slug: slug)
```

- [ ] **Step 5: Create the tools**

`lib/newton/mcp/tools/list_posts.ex`:

```elixir
defmodule Newton.MCP.Tools.ListPosts do
  @moduledoc "Lists this site's posts — drafts included — with their publish status."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Newton.Blog

  schema do
    field :status, :enum,
      values: ["all", "draft", "published"],
      default: "all",
      description: "filter by publish status"
  end

  @impl true
  def execute(params, frame) do
    Newton.Telemetry.span(:mcp, :tool_call, %{tool: "list_posts"}, fn ->
      rows =
        params
        |> Map.get(:status, "all")
        |> filter()
        |> Blog.list_posts()
        |> Enum.map(
          &%{slug: &1.slug, title: &1.title, status: status_of(&1), updated_at: &1.updated_at}
        )

      {{:reply, Response.json(Response.tool(), rows), frame}, %{tool: "list_posts", result: :ok}}
    end)
  end

  defp filter("draft"), do: :drafts
  defp filter("published"), do: :published
  defp filter(_), do: :all

  defp status_of(post), do: if(post.published_at, do: "published", else: "draft")
end
```

`lib/newton/mcp/tools/read_post.ex`:

```elixir
defmodule Newton.MCP.Tools.ReadPost do
  @moduledoc "Reads one post by slug — the markdown source, drafts included."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Newton.Blog

  schema do
    field :slug, :string, required: true, description: "the post's slug"
  end

  @impl true
  def execute(%{slug: slug}, frame) do
    Newton.Telemetry.span(:mcp, :tool_call, %{tool: "read_post"}, fn ->
      case Blog.get_post_by_slug(slug) do
        nil ->
          reply = Response.error(Response.tool(), "no post with slug #{inspect(slug)}")
          {{:reply, reply, frame}, %{tool: "read_post", result: :not_found}}

        post ->
          payload = %{
            slug: post.slug,
            title: post.title,
            status: if(post.published_at, do: "published", else: "draft"),
            excerpt: post.excerpt,
            body_markdown: post.body_markdown
          }

          {{:reply, Response.json(Response.tool(), payload), frame}, %{tool: "read_post", result: :ok}}
      end
    end)
  end
end
```

- [ ] **Step 6: Declare the metric**

In `lib/newton/metrics.ex`, add to the list in `definitions/0`:

```elixir
      distribution("newton.mcp.tool_call.stop.duration",
        event_name: [:newton, :mcp, :tool_call, :stop],
        unit: {:native, :millisecond},
        tags: [:tool, :result],
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 1_000]]
      )
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `mix test test/newton/mcp/tools_test.exs test/newton/blog_test.exs test/newton/metrics_test.exs`
Expected: all PASS (metrics_test guards the definitions list shape; if it asserts an exact metric count, update that count).

- [ ] **Step 8: Format and commit**

```bash
mix format
git add mix.exs mix.lock lib/newton/blog.ex lib/newton/mcp lib/newton/metrics.ex test/newton/mcp test/newton/blog_test.exs test/newton/metrics_test.exs
git commit -m "Add MCP read tools over the blog context"
```

---

### Task 2: Server module, token validator, supervision, and routing

**Files:**
- Create: `lib/newton/mcp/server.ex`
- Create: `lib/newton/mcp/token_validator.ex`
- Modify: `lib/newton/application.ex` (one child after `NewtonWeb.Endpoint`)
- Modify: `lib/newton_web/router.ex` (one pipeline-less scope with two forwards)
- Test: `test/newton/mcp/token_validator_test.exs`
- Test: `test/newton_web/mcp_auth_test.exs`

**Interfaces:**
- Consumes: Task 1's tool modules; plan 1's `Newton.OAuth.verify_access_token/1` and `canonical_resource/0`
- Produces: `Newton.MCP.Server` (anubis server), `Newton.MCP.TokenValidator`, routes `/mcp` and `/.well-known/oauth-protected-resource`

- [ ] **Step 1: Write the failing tests**

Create `test/newton/mcp/token_validator_test.exs`:

```elixir
defmodule Newton.MCP.TokenValidatorTest do
  use Newton.DataCase, async: true

  alias Newton.MCP.TokenValidator
  alias Newton.OAuth

  defp valid_access_token do
    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
        "token_endpoint_auth_method" => "none"
      })

    verifier = OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    {:ok, code} =
      OAuth.issue_code(
        client,
        "https://claude.ai/api/mcp/auth_callback",
        challenge,
        OAuth.canonical_resource()
      )

    {:ok, %{access_token: token}} =
      OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

    token
  end

  test "accepts a live token bound to the MCP resource" do
    assert {:ok, claims} = TokenValidator.validate_token(valid_access_token(), [])
    assert claims["aud"] == OAuth.canonical_resource()
  end

  test "rejects garbage and empty tokens" do
    assert {:error, _} = TokenValidator.validate_token("garbage", [])
    assert {:error, _} = TokenValidator.validate_token("", [])
  end
end
```

Create `test/newton_web/mcp_auth_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/mcp/token_validator_test.exs test/newton_web/mcp_auth_test.exs`
Expected: FAIL — modules and routes missing.

- [ ] **Step 3: Create validator and server**

`lib/newton/mcp/token_validator.ex`:

```elixir
defmodule Newton.MCP.TokenValidator do
  @moduledoc "Anubis bearer validator backed by Newton.OAuth's hashed token store."

  @behaviour Anubis.Server.Authorization.Validator

  alias Newton.OAuth

  @impl true
  def validate_token(token, _config) do
    with {:ok, claims} <- OAuth.verify_access_token(token),
         true <- claims["aud"] == OAuth.canonical_resource() do
      {:ok, claims}
    else
      _ -> {:error, :invalid_token}
    end
  end
end
```

`lib/newton/mcp/server.ex`:

```elixir
defmodule Newton.MCP.Server do
  @moduledoc "MCP server exposing read-only post tools, drafts included."

  use Anubis.Server,
    name: "jamesnewton.com",
    version: "1.0.0",
    capabilities: [:tools]

  component Newton.MCP.Tools.ListPosts
  component Newton.MCP.Tools.ReadPost

  @impl true
  def init(_client_info, frame), do: {:ok, frame}
end
```

- [ ] **Step 4: Supervise and route**

In `lib/newton/application.ex`, add after `NewtonWeb.Endpoint` in the children list:

```elixir
      {Newton.MCP.Server,
       transport: :streamable_http,
       authorization: [
         authorization_servers: [Newton.OAuth.canonical_resource() |> String.trim_trailing("/mcp")],
         resource: Newton.OAuth.canonical_resource(),
         validator: {Newton.MCP.TokenValidator, []}
       ]}
```

In `lib/newton_web/router.ex`, add near the other top-level scopes (no `pipe_through` — anubis owns auth and content negotiation here, and browser plugs would CSRF-reject POSTs and break SSE):

```elixir
  scope "/" do
    forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: Newton.MCP.Server

    forward "/.well-known/oauth-protected-resource", Anubis.Server.Transport.WellKnown,
      server: Newton.MCP.Server
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton/mcp/token_validator_test.exs test/newton_web/mcp_auth_test.exs`
Expected: all PASS. If the WellKnown metadata test fails on key names, print the JSON body and match assertions to anubis's actual field names (`resource` and `authorization_servers` per its docs) — do not weaken the resource/AS URL assertions themselves.

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/newton/mcp lib/newton/application.ex lib/newton_web/router.ex test/newton/mcp/token_validator_test.exs test/newton_web/mcp_auth_test.exs
git commit -m "Mount the OAuth-guarded MCP server"
```

---

### Task 3: End-to-end flow test and spec amendment

**Files:**
- Test: `test/newton_web/mcp_end_to_end_test.exs`
- Modify: `docs/superpowers/specs/2026-08-17-mcp-server-oauth-design.md` (three factual amendments below)

**Interfaces:**
- Consumes: everything from plan 1 and Tasks 1–2
- Produces: nothing new — this task proves the whole pipe and trues up the spec

- [ ] **Step 1: Write the end-to-end test**

Create `test/newton_web/mcp_end_to_end_test.exs`:

```elixir
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
```

(As in plan tasks before it: if `Blog.create_post/1` differs, mirror `blog_test.exs`'s draft creation. If the initialize response nests differently, print `parse_jsonrpc(init_conn.resp_body)` once and align the assertion — keep the substance: handshake succeeds, tool call returns the draft body without error.)

- [ ] **Step 2: Run it**

Run: `mix test test/newton_web/mcp_end_to_end_test.exs`
Expected: PASS. This is the proof the two plans compose.

- [ ] **Step 3: Amend the spec to match reality**

In `docs/superpowers/specs/2026-08-17-mcp-server-oauth-design.md`, make exactly these corrections:

1. Replace both mentions of `hermes_mcp` with `anubis_mcp ~> 2.0`, with the parenthetical "(maintained fork of hermes_mcp; hermes upstream deleted, frozen at 0.14.1)".
2. In the table/model section, rename `oauth_tokens` to `oauth_grants` (the implemented table name).
3. In the MCP server and endpoint sections, note that anubis's transport itself serves `/.well-known/oauth-protected-resource` and emits 401 + `WWW-Authenticate` (via `Newton.MCP.TokenValidator`), replacing the hand-written bearer plug and metadata endpoint the spec originally assumed.

- [ ] **Step 4: Run the full gate**

Run: `mix precommit`
Expected: clean.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add test/newton_web/mcp_end_to_end_test.exs docs/superpowers/specs/2026-08-17-mcp-server-oauth-design.md
git commit -m "Prove the OAuth-to-MCP flow end to end"
```
