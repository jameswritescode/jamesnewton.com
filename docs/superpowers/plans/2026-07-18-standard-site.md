# Standard.site Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish posts as `site.standard.*` AT Protocol records (metadata-only) synced on publish, with the site serving the standard's verification surface.

**Architecture:** `Newton.Standard` (Req XRPC client, session-per-call, prod-gated, telemetry-spanned) is a sibling of `Newton.IndexNow`. The editor's notifier seam generalizes: `NewtonWeb.IndexNowNotifier` becomes `NewtonWeb.PublicationNotifier`, computing the publish transition once and fanning out to both targets in separate supervised tasks. Verification: a `.well-known` route plus two head link tags; record keys are post slugs, so document AT-URIs are computable with no schema changes.

**Tech Stack:** Req (existing), `Newton.Telemetry`/`Newton.Metrics` (existing), no new deps.

**Spec:** `docs/superpowers/specs/2026-07-18-standard-site-design.md`

## Global Constraints

- Exact identity values, verbatim everywhere they appear:
  - DID: `did:plc:engjedcb3kwfl4vuo5gtr6n4`
  - handle/identifier: `jamesnewton.com`
  - PDS: `https://bsky.social`
  - publication rkey: `self`; document rkey: the post slug
  - publication record: url `https://jamesnewton.com`, name `James Newton`, description `Software & Photography`, `preferences.showInDiscover: true`
  - publication AT-URI (deterministic, since rkey is `self`): `at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.publication/self` — configured from day one (a deliberate refinement of the spec's "set after the mix task": the URI is knowable now; the mix task confirms rather than mints it)
- Document records are metadata-only, exactly: `$type`, `site`, `title`, `path` (`/posts/<slug>`), `publishedAt` (ISO8601), `description` (excerpt).
- `enabled: false` in every environment (launch flips prod — see `docs/production.md`); `put_publication/0` alone bypasses the gate.
- Telemetry: emission only via `Newton.Telemetry.span(:standard, :sync, ...)`; metric declared once in `Newton.Metrics` with tags `[:operation, :result]` (bounded: 3 ops × 2 results) and buckets exactly `[100, 250, 500, 1_000, 2_500, 5_000]` ms. Slugs may appear in logs, never in metric metadata.
- **The refactor must be behavior-preserving for IndexNow:** existing notifier URL tests and the editor IndexNow integration test pass with only module-name updates.
- App password comes only from `BSKY_APP_PASSWORD` (runtime env); never a literal anywhere.
- Commits allowed (signing is up): commit per task with the trailers:

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01J6oUv9UTDpHJ9Z2bxXCzTX
- No narrating comments; domain `@spec`s; `mix format` per touched file; finish with `mix precommit` (Task 3).

---

### Task 1: `Newton.Standard` client, config, metric, mix task

**Files:**
- Create: `lib/newton/standard.ex`
- Create: `lib/mix/tasks/standard.put_publication.ex`
- Modify: `config/config.exs` (before the `import_config` line)
- Modify: `config/test.exs` (append)
- Modify: `config/runtime.exs` (prod block, after the `:webauthn` config)
- Modify: `lib/newton/metrics.ex` (add one distribution)
- Test: `test/newton/standard_test.exs`

**Interfaces:**
- Consumes: `Newton.Telemetry.span/4` (existing).
- Produces (Tasks 2/3 depend on these exact signatures):
  - `Newton.Standard.put_document(%Newton.Blog.Post{}) :: :ok | {:error, term()}`
  - `Newton.Standard.delete_document(String.t()) :: :ok | {:error, term()}`
  - `Newton.Standard.put_publication() :: {:ok, String.t()} | {:error, term()}`
  - `Newton.Standard.publication_uri() :: String.t() | nil`
  - `Newton.Standard.document_uri(String.t()) :: String.t() | nil`

- [ ] **Step 1: Configuration**

`config/config.exs`, after the `Newton.IndexNow` block:

```elixir
config :newton, Newton.Standard,
  enabled: false,
  identifier: "jamesnewton.com",
  did: "did:plc:engjedcb3kwfl4vuo5gtr6n4",
  pds_url: "https://bsky.social",
  publication_uri: "at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.publication/self"
```

`config/test.exs`, at the end:

```elixir
config :newton, Newton.Standard,
  app_password: "test-app-password",
  req_options: [plug: {Req.Test, Newton.Standard}]
```

`config/runtime.exs`, inside the `if config_env() == :prod do` block, after the `:webauthn` config:

```elixir
  config :newton, Newton.Standard, app_password: System.get_env("BSKY_APP_PASSWORD")
```

- [ ] **Step 2: Write the failing tests**

Create `test/newton/standard_test.exs`:

```elixir
defmodule Newton.StandardTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Newton.Blog.Post
  alias Newton.Standard

  @did "did:plc:engjedcb3kwfl4vuo5gtr6n4"
  @publication "at://#{@did}/site.standard.publication/self"

  @post %Post{
    slug: "hello-world",
    title: "Hello World",
    excerpt: "A first post.",
    published_at: ~U[2026-07-18 12:00:00Z]
  }

  defp enable(overrides \\ []) do
    config = Application.get_env(:newton, Standard)

    Application.put_env(
      :newton,
      Standard,
      config |> Keyword.put(:enabled, true) |> Keyword.merge(overrides)
    )

    on_exit(fn -> Application.put_env(:newton, Standard, config) end)
  end

  defp stub_pds(responder \\ nil) do
    test_pid = self()

    Req.Test.stub(Standard, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:xrpc, conn.request_path, Jason.decode!(body)})

      case responder do
        nil -> Req.Test.json(conn, %{"accessJwt" => "tok", "did" => @did})
        fun -> fun.(conn)
      end
    end)
  end

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :standard, :sync, :stop]])
    %{ref: ref}
  end

  test "put_document creates a session then puts a metadata-only record keyed by slug", %{
    ref: ref
  } do
    enable()
    stub_pds()

    assert Standard.put_document(@post) == :ok

    assert_received {:xrpc, "/xrpc/com.atproto.server.createSession",
                     %{"identifier" => "jamesnewton.com", "password" => "test-app-password"}}

    assert_received {:xrpc, "/xrpc/com.atproto.repo.putRecord", body}

    assert body == %{
             "repo" => @did,
             "collection" => "site.standard.document",
             "rkey" => "hello-world",
             "record" => %{
               "$type" => "site.standard.document",
               "site" => @publication,
               "title" => "Hello World",
               "path" => "/posts/hello-world",
               "publishedAt" => "2026-07-18T12:00:00Z",
               "description" => "A first post."
             }
           }

    assert_received {[:newton, :standard, :sync, :stop], ^ref, %{duration: _},
                     %{operation: :put_document, result: :ok}}
  end

  test "delete_document removes the slug's record" do
    enable()
    stub_pds()

    assert Standard.delete_document("hello-world") == :ok

    assert_received {:xrpc, "/xrpc/com.atproto.repo.deleteRecord",
                     %{
                       "repo" => @did,
                       "collection" => "site.standard.document",
                       "rkey" => "hello-world"
                     }}
  end

  test "put_publication writes the self record and returns its AT-URI without the enabled gate" do
    stub_pds()

    assert Standard.put_publication() == {:ok, @publication}

    assert_received {:xrpc, "/xrpc/com.atproto.repo.putRecord", body}

    assert body == %{
             "repo" => @did,
             "collection" => "site.standard.publication",
             "rkey" => "self",
             "record" => %{
               "$type" => "site.standard.publication",
               "url" => "https://jamesnewton.com",
               "name" => "James Newton",
               "description" => "Software & Photography",
               "preferences" => %{"showInDiscover" => true}
             }
           }
  end

  test "disabled is a silent no-op for document calls", %{ref: ref} do
    assert Standard.put_document(@post) == :ok
    assert Standard.delete_document("hello-world") == :ok
    refute_received {:xrpc, _, _}
    refute_received {[:newton, :standard, :sync, :stop], ^ref, _, _}
  end

  test "enabled without a publication_uri refuses loudly" do
    enable(publication_uri: nil)

    log =
      capture_log(fn ->
        assert Standard.put_document(@post) == {:error, :publication_not_configured}
      end)

    assert log =~ "publication_uri"
    refute_received {:xrpc, _, _}
  end

  test "a failed session propagates as an error", %{ref: ref} do
    enable()
    stub_pds(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    log =
      capture_log(fn ->
        assert {:error, {:session, 401}} = Standard.put_document(@post)
      end)

    assert log =~ "put_document"

    assert_received {[:newton, :standard, :sync, :stop], ^ref, %{duration: _},
                     %{operation: :put_document, result: :error}}
  end

  test "a non-2xx record write propagates as an error" do
    enable()
    test_pid = self()

    Req.Test.stub(Standard, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      if String.ends_with?(conn.request_path, "createSession") do
        send(test_pid, :session_ok)
        Req.Test.json(conn, %{"accessJwt" => "tok", "did" => @did})
      else
        Plug.Conn.send_resp(conn, 502, "")
      end
    end)

    log =
      capture_log(fn ->
        assert {:error, {:status, 502}} = Standard.put_document(@post)
      end)

    assert_received :session_ok
    assert log =~ "put_document"
  end

  test "URI helpers derive from config" do
    assert Standard.publication_uri() == @publication
    assert Standard.document_uri("some-slug") == "at://#{@did}/site.standard.document/some-slug"
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton/standard_test.exs`
Expected: FAIL — `Newton.Standard` is undefined.

- [ ] **Step 4: Implement the client**

Create `lib/newton/standard.ex`:

```elixir
defmodule Newton.Standard do
  @moduledoc """
  Publishes site.standard.* records to the author's AT Protocol repo so
  ATmosphere apps can follow and discover the site. Documents are metadata
  only; readers follow the canonical URL to the site.
  """
  require Logger

  alias Newton.Blog.Post

  @spec put_document(%Post{}) :: :ok | {:error, term()}
  def put_document(%Post{} = post) do
    config = config()

    cond do
      !config[:enabled] ->
        :ok

      is_nil(config[:publication_uri]) ->
        Logger.error("standard.site is enabled but publication_uri is not configured")
        {:error, :publication_not_configured}

      true ->
        record = %{
          "$type" => "site.standard.document",
          "site" => config[:publication_uri],
          "title" => post.title,
          "path" => "/posts/#{post.slug}",
          "publishedAt" => DateTime.to_iso8601(post.published_at),
          "description" => post.excerpt
        }

        sync(:put_document, config, fn token ->
          xrpc(config, token, "com.atproto.repo.putRecord", %{
            repo: config[:did],
            collection: "site.standard.document",
            rkey: post.slug,
            record: record
          })
        end)
    end
  end

  @spec delete_document(String.t()) :: :ok | {:error, term()}
  def delete_document(slug) when is_binary(slug) do
    config = config()

    if config[:enabled] do
      sync(:delete_document, config, fn token ->
        xrpc(config, token, "com.atproto.repo.deleteRecord", %{
          repo: config[:did],
          collection: "site.standard.document",
          rkey: slug
        })
      end)
    else
      :ok
    end
  end

  @spec put_publication() :: {:ok, String.t()} | {:error, term()}
  def put_publication do
    config = config()

    record = %{
      "$type" => "site.standard.publication",
      "url" => "https://jamesnewton.com",
      "name" => "James Newton",
      "description" => "Software & Photography",
      "preferences" => %{"showInDiscover" => true}
    }

    result =
      sync(:put_publication, config, fn token ->
        xrpc(config, token, "com.atproto.repo.putRecord", %{
          repo: config[:did],
          collection: "site.standard.publication",
          rkey: "self",
          record: record
        })
      end)

    with :ok <- result do
      {:ok, "at://#{config[:did]}/site.standard.publication/self"}
    end
  end

  @spec publication_uri() :: String.t() | nil
  def publication_uri, do: config()[:publication_uri]

  @spec document_uri(String.t()) :: String.t() | nil
  def document_uri(slug) do
    with did when is_binary(did) <- config()[:did] do
      "at://#{did}/site.standard.document/#{slug}"
    end
  end

  defp sync(operation, config, fun) do
    Newton.Telemetry.span(:standard, :sync, %{operation: operation}, fn ->
      outcome =
        with {:ok, token} <- create_session(config) do
          fun.(token)
        end

      case outcome do
        :ok ->
          {:ok, %{operation: operation, result: :ok}}

        {:error, reason} ->
          Logger.warning("standard.site #{operation} failed: #{inspect(reason)}")
          {{:error, reason}, %{operation: operation, result: :error}}
      end
    end)
  end

  defp create_session(config) do
    body = %{identifier: config[:identifier], password: config[:app_password]}

    case Req.post(xrpc_url(config, "com.atproto.server.createSession"),
           [json: body] ++ req_options(config)
         ) do
      {:ok, %Req.Response{status: 200, body: %{"accessJwt" => token}}} -> {:ok, token}
      {:ok, %Req.Response{status: status}} -> {:error, {:session, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp xrpc(config, token, method, body) do
    case Req.post(xrpc_url(config, method),
           [json: body, auth: {:bearer, token}] ++ req_options(config)
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp xrpc_url(config, method), do: "#{config[:pds_url]}/xrpc/#{method}"
  defp req_options(config), do: Keyword.get(config, :req_options, [])
  defp config, do: Application.get_env(:newton, __MODULE__, [])
end
```

Note on `sync/3`'s return plumbing: `Newton.Telemetry.span/4` returns the
FIRST element of the `{result, stop_meta}` tuple the fun returns. The fun
above returns `{:ok, meta}` on success and `{{:error, reason}, meta}` on
failure, so `sync/3` returns `:ok | {:error, reason}` directly — do not wrap
the span in any further case/normalization.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/newton/standard_test.exs`
Expected: 8 tests, 0 failures. (If `assert_received {:xrpc, ...}` on the
session body fails because `password` differs: the test env sets
`app_password: "test-app-password"` — check Step 1's test.exs block landed.)

- [ ] **Step 6: Declare the metric**

In `lib/newton/metrics.ex`, add to `definitions/0` after the analytics entry:

```elixir
      distribution("newton.standard.sync.stop.duration",
        event_name: [:newton, :standard, :sync, :stop],
        unit: {:native, :millisecond},
        tags: [:operation, :result],
        reporter_options: [buckets: [100, 250, 500, 1_000, 2_500, 5_000]]
      )
```

Run: `mix test test/newton/metrics_test.exs`
Expected: guard tests pass (no summary, buckets present).

- [ ] **Step 7: The mix task**

Create `lib/mix/tasks/standard.put_publication.ex`:

```elixir
defmodule Mix.Tasks.Standard.PutPublication do
  @shortdoc "Creates or updates the site.standard.publication record"

  @moduledoc """
  Writes the publication record to the author's PDS repo. Requires
  BSKY_APP_PASSWORD in the environment. Runs regardless of the enabled flag —
  an explicit operator action. Idempotent: rkey "self" upserts.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    password =
      System.get_env("BSKY_APP_PASSWORD") ||
        Mix.raise("BSKY_APP_PASSWORD is not set")

    config = Application.get_env(:newton, Newton.Standard, [])
    Application.put_env(:newton, Newton.Standard, Keyword.put(config, :app_password, password))

    case Newton.Standard.put_publication() do
      {:ok, uri} -> Mix.shell().info("publication record: #{uri}")
      {:error, reason} -> Mix.raise("put_publication failed: #{inspect(reason)}")
    end
  end
end
```

(No test for the task itself — it is a thin shell over `put_publication/0`,
which Step 2 covers including the no-gate behavior.)

- [ ] **Step 8: Full guard run + commit**

Run: `mix test test/newton/standard_test.exs test/newton/metrics_test.exs test/newton/index_now_test.exs`
Expected: all pass.

```bash
git add lib/newton/standard.ex lib/mix/tasks/standard.put_publication.ex config/config.exs config/test.exs config/runtime.exs lib/newton/metrics.ex test/newton/standard_test.exs
git commit -m "Add a standard.site client for AT Protocol records"
```

(Append the trailers from Global Constraints to the commit message.)

---

### Task 2: `PublicationNotifier` fan-out + editor rename

**Files:**
- Rename+rewrite: `lib/newton_web/index_now_notifier.ex` → `lib/newton_web/publication_notifier.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (alias line 12; call sites at lines 97, 304, 325, 348, 468, 479, 494 — rename only)
- Rename+extend: `test/newton_web/index_now_notifier_test.exs` → `test/newton_web/publication_notifier_test.exs`
- Create: `test/newton_web/live/admin/post_editor_standard_test.exs`

**Interfaces:**
- Consumes: `Newton.Standard.put_document/1`, `delete_document/1` (Task 1); `Newton.IndexNow.submit/1` (existing).
- Produces: `NewtonWeb.PublicationNotifier.notify_change(%Post{} | nil, %Post{} | nil) :: :ok`; `changed_urls/2` (unchanged semantics); `standard_ops(%Post{} | nil, %Post{} | nil) :: [{:put_document, %Post{}} | {:delete_document, String.t()}]`.

- [ ] **Step 1: Rename the notifier test file and add the failing standard_ops tests**

`git mv test/newton_web/index_now_notifier_test.exs test/newton_web/publication_notifier_test.exs`,
rename the module to `NewtonWeb.PublicationNotifierTest`, change the alias to
`alias NewtonWeb.PublicationNotifier` and every `IndexNowNotifier.` call to
`PublicationNotifier.` — the existing `changed_urls` assertions stay
byte-identical. Then add:

```elixir
  test "draft-only mutations produce no standard operations" do
    assert PublicationNotifier.standard_ops(@draft, @draft) == []
    assert PublicationNotifier.standard_ops(nil, @draft) == []
    assert PublicationNotifier.standard_ops(@draft, nil) == []
    assert PublicationNotifier.standard_ops(nil, nil) == []
  end

  test "publishing puts the document" do
    assert PublicationNotifier.standard_ops(@draft, @published) == [{:put_document, @published}]
    assert PublicationNotifier.standard_ops(nil, @published) == [{:put_document, @published}]
  end

  test "editing a published post re-puts the document" do
    assert PublicationNotifier.standard_ops(@published, @published) ==
             [{:put_document, @published}]
  end

  test "a slug change deletes the old record and puts the new one" do
    renamed = %Post{@published | slug: "renamed"}

    assert PublicationNotifier.standard_ops(@published, renamed) ==
             [{:delete_document, "hello"}, {:put_document, renamed}]
  end

  test "unpublishing and deleting remove the record" do
    assert PublicationNotifier.standard_ops(@published, @draft) == [{:delete_document, "hello"}]
    assert PublicationNotifier.standard_ops(@published, nil) == [{:delete_document, "hello"}]
  end
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `mix test test/newton_web/publication_notifier_test.exs`
Expected: `changed_urls` tests fail to compile or the file errors —
`NewtonWeb.PublicationNotifier` undefined.

- [ ] **Step 3: Rename and rewrite the notifier**

`git mv lib/newton_web/index_now_notifier.ex lib/newton_web/publication_notifier.ex`,
full new content:

```elixir
defmodule NewtonWeb.PublicationNotifier do
  @moduledoc """
  Fans a post mutation out to every syndication target: IndexNow (changed
  URLs) and standard.site (document records). Draft-only mutations notify
  nothing. Each target runs in its own supervised task so one failing
  integration cannot starve another.
  """
  use NewtonWeb, :verified_routes
  require Logger

  alias Newton.Blog.Post
  alias Newton.IndexNow
  alias Newton.Standard

  @spec notify_change(%Post{} | nil, %Post{} | nil) :: :ok
  def notify_change(before_post, after_post) do
    case changed_urls(before_post, after_post) do
      [] -> :ok
      urls -> start_task(IndexNow, :submit, [urls], "IndexNow")
    end

    for {fun, arg} <- standard_ops(before_post, after_post) do
      start_task(Standard, fun, [arg], "standard.site")
    end

    :ok
  end

  @spec changed_urls(%Post{} | nil, %Post{} | nil) :: [String.t()]
  def changed_urls(before_post, after_post) do
    case post_urls(before_post) ++ post_urls(after_post) do
      [] -> []
      urls -> Enum.uniq(urls) ++ [url(~p"/"), url(~p"/posts")]
    end
  end

  @spec standard_ops(%Post{} | nil, %Post{} | nil) ::
          [{:put_document, %Post{}} | {:delete_document, String.t()}]
  def standard_ops(before_post, after_post) do
    case {published(before_post), published(after_post)} do
      {nil, nil} -> []
      {nil, post} -> [{:put_document, post}]
      {post, nil} -> [{:delete_document, post.slug}]
      {%Post{slug: slug}, %Post{slug: slug} = post} -> [{:put_document, post}]
      {old, post} -> [{:delete_document, old.slug}, {:put_document, post}]
    end
  end

  defp published(%Post{published_at: %DateTime{}} = post), do: post
  defp published(_), do: nil

  defp post_urls(%Post{published_at: %DateTime{}, slug: slug}), do: [url(~p"/posts/#{slug}")]
  defp post_urls(_), do: []

  defp start_task(mod, fun, args, label) do
    case Task.Supervisor.start_child(Newton.TaskSupervisor, mod, fun, args) do
      {:ok, _pid} -> :ok
      {:error, reason} -> Logger.warning("#{label} task not started: #{inspect(reason)}")
    end
  end
end
```

- [ ] **Step 4: Rename the editor call sites**

In `lib/newton_web/live/admin/post_live/editor.ex`: line 12 alias becomes
`alias NewtonWeb.PublicationNotifier`; the seven call sites (97, 304, 325,
348, 468, 479, 494) become `PublicationNotifier.notify_change(...)` — the
arguments are untouched.

- [ ] **Step 5: Run the renamed + existing suites**

Run: `mix test test/newton_web/publication_notifier_test.exs test/newton_web/live/admin/post_editor_index_now_test.exs`
Expected: all pass — the IndexNow integration test proves the refactor is
behavior-preserving (it stubs `Newton.IndexNow` and exercises a real publish).

- [ ] **Step 6: The standard-side editor integration test**

Create `test/newton_web/live/admin/post_editor_standard_test.exs`:

```elixir
defmodule NewtonWeb.Admin.PostEditorStandardTest do
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    config = Application.get_env(:newton, Newton.Standard)
    Application.put_env(:newton, Newton.Standard, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, Newton.Standard, config) end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  test "publishing a post puts its standard.site record", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Standard post",
        slug: "standard-post",
        body_markdown: "Hello."
      })

    test_pid = self()

    Req.Test.stub(Newton.Standard, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:xrpc, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{"accessJwt" => "tok"})
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    render_click(view, "publish_now", %{})

    assert_receive {:xrpc, "/xrpc/com.atproto.repo.putRecord", %{"rkey" => "standard-post"}},
                   2_000
  end
end
```

- [ ] **Step 7: Run it**

Run: `mix test test/newton_web/live/admin/post_editor_standard_test.exs`
Expected: 1 test, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/publication_notifier.ex lib/newton_web/live/admin/post_live/editor.ex test/newton_web/publication_notifier_test.exs test/newton_web/live/admin/post_editor_standard_test.exs
git rm --cached lib/newton_web/index_now_notifier.ex test/newton_web/index_now_notifier_test.exs 2>/dev/null || true
git commit -m "Fan publish notifications out to IndexNow and standard.site"
```

(`git mv` already staged the renames; the `git rm --cached` guard is a no-op
then. Append the trailers.)

---

### Task 3: Verification surface + gate

**Files:**
- Create: `lib/newton_web/controllers/standard_controller.ex`
- Modify: `lib/newton_web/router.ex` (crawler scope, after the robots route)
- Modify: `lib/newton_web/components/layouts/root.html.heex` (head, after the `<SEO.juice ...>` line)
- Modify: `lib/newton_web/controllers/post_controller.ex` (published branch of `show/2`)
- Test: `test/newton_web/controllers/standard_meta_test.exs`

**Interfaces:**
- Consumes: `Newton.Standard.publication_uri/0`, `document_uri/1` (Task 1).
- Produces: `GET /.well-known/site.standard.publication`; head link tags.

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/controllers/standard_meta_test.exs`:

```elixir
defmodule NewtonWeb.StandardMetaTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  @publication "at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.publication/self"

  defp published_post do
    {:ok, post} =
      Blog.create_post(%{
        slug: "standard-meta-post",
        title: "Standard Meta Post",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    post
  end

  test "the well-known endpoint serves the publication AT-URI", %{conn: conn} do
    conn = get(conn, "/.well-known/site.standard.publication")

    assert response_content_type(conn, :text) =~ "text/plain"
    assert response(conn, 200) == @publication
  end

  test "a published post page links its document record", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    assert html =~
             ~s(<link rel="site.standard.document" href="at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.document/standard-meta-post">)

    assert html =~ ~s(<link rel="site.standard.publication" href="#{@publication}">)
  end

  test "preview pages carry no document link", %{conn: conn} do
    {:ok, post} =
      Blog.create_post(%{slug: "standard-draft", title: "Draft", body_markdown: "Shh."})

    {:ok, post} = Blog.enable_preview(post)

    html = conn |> get(~p"/posts/#{post.slug}?p=#{post.preview_token}") |> html_response(200)

    refute html =~ ~s(rel="site.standard.document")
  end

  test "non-post pages carry no document link", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ ~s(rel="site.standard.document")
    assert html =~ ~s(rel="site.standard.publication")
  end
end
```

Note: if the link-tag assertions fail on attribute order or self-closing
slashes, relax to two `=~` checks per tag (one for `rel=`, one for `href=`)
scoped by the AT-URI — assert behavior (tag present with right target), not
exact serialization.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/controllers/standard_meta_test.exs`
Expected: FAIL — no route, no link tags.

- [ ] **Step 3: Controller + route**

Create `lib/newton_web/controllers/standard_controller.ex`:

```elixir
defmodule NewtonWeb.StandardController do
  @moduledoc "Serves the standard.site publication pointer for AppView verification."
  use NewtonWeb, :controller

  def publication(conn, _params) do
    case Newton.Standard.publication_uri() do
      nil ->
        send_resp(conn, 404, "")

      uri ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, uri)
    end
  end
end
```

In `lib/newton_web/router.ex`, inside the existing crawler scope (the one
holding `/sitemap.xml` and `/robots.txt`), add:

```elixir
    get "/.well-known/site.standard.publication", StandardController, :publication
```

- [ ] **Step 4: Link tags**

`lib/newton_web/components/layouts/root.html.heex` — directly after the
`<SEO.juice ...>` line:

```heex
    <link
      :if={publication_uri = Newton.Standard.publication_uri()}
      rel="site.standard.publication"
      href={publication_uri}
    />
    <link
      :if={assigns[:standard_document]}
      rel="site.standard.document"
      href={@standard_document}
    />
```

`lib/newton_web/controllers/post_controller.ex` — in `show/2`, the published
(non-preview) branch only, add alongside the existing assigns:

```elixir
        |> assign(:standard_document, Newton.Standard.document_uri(post.slug))
```

(The preview branch gets no assign — the `:if` keeps the tag off previews,
drafts, and every non-post page.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/newton_web/controllers/standard_meta_test.exs test/newton_web/controllers/seo_meta_test.exs`
Expected: all pass (seo_meta_test guards against head regressions).

- [ ] **Step 6: Full gate**

Run: `mix precommit`
Expected: clean (dialyzer: 3 known phoenix_seo skips). Fix anything raised.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/controllers/standard_controller.ex lib/newton_web/router.ex lib/newton_web/components/layouts/root.html.heex lib/newton_web/controllers/post_controller.ex test/newton_web/controllers/standard_meta_test.exs
git commit -m "Serve the standard.site verification surface"
```

(Append the trailers.)
