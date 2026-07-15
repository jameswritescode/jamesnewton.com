# Sitemap + IndexNow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve a dynamic `sitemap.xml` + `robots.txt`, and notify IndexNow-participating search engines automatically when published posts change.

**Architecture:** A pipeline-less `SitemapController` renders XML via `xml_builder` from `Blog.list_published_posts()`. A `Newton.Telemetry` facade owns the `[:newton, ...]` event prefix. `Newton.IndexNow` POSTs changed URLs to `api.indexnow.org` (Req, telemetry span, prod-only). `NewtonWeb.IndexNowNotifier` computes changed-URL sets from before/after post states and fires submissions through a `Task.Supervisor` from the admin editor's mutation points.

**Tech Stack:** Phoenix 1.8, `xml_builder ~> 2.4` (new dep), Req (existing), `:telemetry` + `Telemetry.Metrics` (existing).

**Spec:** `docs/superpowers/specs/2026-07-15-sitemap-indexnow-design.md`

## Global Constraints

- **No narrating comments** — comments only for constraints the code can't express (AGENTS.md).
- **HTTP via Req only** — never httpoison/tesla/httpc (AGENTS.md).
- **Telemetry emission goes through `Newton.Telemetry`**, never raw `:telemetry` at call sites. Event name: `[:newton, :indexnow, :submit]`. Metric tags/metadata must be bounded values (result atom, HTTP status, url_count) — **never URLs, slugs, or IDs** (AGENTS.md observability section). URLs may appear in log messages, not metric dimensions.
- **Test behaviors, not structure** (AGENTS.md test guidelines).
- **IndexNow key literal (everywhere it appears):** `d1258f1d59aea5c8f3e604eb494cc477`
- **Cache-control for sitemap/robots:** `public, max-age=3600` (matches og endpoint).
- **`lastmod`** date-only ISO 8601, post entries only. **No `changefreq`/`priority`.**
- Sitemap static pages, exactly: `/`, `/posts`, `/reading`, `/photos`, `/links`, `/resume`.
- IndexNow enabled **only in prod**; dev/test default disabled.
- Finish with `mix precommit` (Task 4, final step) and fix anything it raises.

---

### Task 1: SitemapController — sitemap.xml + dynamic robots.txt

**Files:**
- Modify: `mix.exs` (deps, ~line 82)
- Create: `lib/newton_web/controllers/sitemap_controller.ex`
- Modify: `lib/newton_web/router.ex` (~line 41, after the `/og` scope)
- Modify: `lib/newton_web.ex:20-22` (static_paths)
- Delete: `priv/static/robots.txt`
- Test: `test/newton_web/controllers/sitemap_controller_test.exs`

**Interfaces:**
- Consumes: `Newton.Blog.list_published_posts/0` (existing; returns post summaries with `:slug`, `:updated_at`).
- Produces: `GET /sitemap.xml` (application/xml), `GET /robots.txt` (text/plain). No later task depends on this one.

- [ ] **Step 1: Add the dependency**

In `mix.exs`, in `defp deps`, after `{:phoenix_seo, "~> 0.3.0-rc.0"}`:

```elixir
      {:phoenix_seo, "~> 0.3.0-rc.0"},
      {:xml_builder, "~> 2.4"}
```

Run: `mix deps.get`
Expected: resolves `xml_builder 2.4.x`, updates `mix.lock`.

- [ ] **Step 2: Write the failing tests**

Create `test/newton_web/controllers/sitemap_controller_test.exs`:

```elixir
defmodule NewtonWeb.SitemapControllerTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  describe "GET /sitemap.xml" do
    test "lists published posts with date-only lastmod plus the static pages", %{conn: conn} do
      {:ok, post} =
        Blog.create_post(%{
          slug: "sitemap-post",
          title: "Sitemap Post",
          body_markdown: "Hello.",
          published_at: DateTime.utc_now()
        })

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert response_content_type(conn, :xml) =~ "application/xml"
      assert body =~ "<loc>#{url(~p"/posts/sitemap-post")}</loc>"
      assert body =~ "<lastmod>#{post.updated_at |> DateTime.to_date() |> Date.to_iso8601()}</lastmod>"

      for path <- ["/", "/posts", "/reading", "/photos", "/links", "/resume"] do
        assert body =~ "<loc>#{NewtonWeb.Endpoint.url() <> path}</loc>"
      end
    end

    test "drafts do not appear", %{conn: conn} do
      {:ok, _draft} =
        Blog.create_post(%{slug: "secret-draft", title: "Draft", body_markdown: "Shh."})

      body = conn |> get(~p"/sitemap.xml") |> response(200)

      refute body =~ "secret-draft"
      refute body =~ "<lastmod>"
    end
  end

  describe "GET /robots.txt" do
    test "allows all crawlers and points at the sitemap", %{conn: conn} do
      conn = get(conn, ~p"/robots.txt")
      body = response(conn, 200)

      assert response_content_type(conn, :text) =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ "Sitemap: #{url(~p"/sitemap.xml")}"
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton_web/controllers/sitemap_controller_test.exs`
Expected: FAIL — `/sitemap.xml` has no route (404 / `Phoenix.Router.NoRouteError`); `/robots.txt` is served by Plug.Static without a `Sitemap:` line.

- [ ] **Step 4: Remove robots.txt from static serving**

In `lib/newton_web.ex`, `static_paths` (~line 20): delete `robots.txt` from the `~w(...)` list:

```elixir
  def static_paths,
    do:
      ~w(assets fonts images favicon.ico favicon.svg favicon-32.png favicon-96.png apple-touch-icon.png og-default.png og-links.png)
```

Then: `git rm priv/static/robots.txt`

- [ ] **Step 5: Create the controller**

Create `lib/newton_web/controllers/sitemap_controller.ex`:

```elixir
defmodule NewtonWeb.SitemapController do
  @moduledoc "Serves sitemap.xml and robots.txt for crawlers."
  use NewtonWeb, :controller

  alias Newton.Blog

  @cache_control "public, max-age=3600"

  def sitemap(conn, _params) do
    xml =
      :urlset
      |> XmlBuilder.document(
        %{xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9"},
        static_entries() ++ post_entries()
      )
      |> XmlBuilder.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", @cache_control)
    |> send_resp(200, xml)
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", @cache_control)
    |> send_resp(200, """
    User-agent: *
    Disallow:

    Sitemap: #{url(~p"/sitemap.xml")}
    """)
  end

  defp static_entries do
    [url(~p"/"), url(~p"/posts"), url(~p"/reading"), url(~p"/photos"), url(~p"/links"), url(~p"/resume")]
    |> Enum.map(&{:url, nil, [{:loc, nil, &1}]})
  end

  defp post_entries do
    for post <- Blog.list_published_posts() do
      {:url, nil,
       [
         {:loc, nil, url(~p"/posts/#{post.slug}")},
         {:lastmod, nil, post.updated_at |> DateTime.to_date() |> Date.to_iso8601()}
       ]}
    end
  end
end
```

Note: `url(~p"...")` requires a literal sigil per call (Phoenix verified routes) — that's why `static_entries/0` lists them out instead of mapping over path strings.

- [ ] **Step 6: Add the routes**

In `lib/newton_web/router.ex`, directly after the `/og` scope block (ends ~line 41), add:

```elixir
  # Crawler endpoints. No :browser pipeline — plain XML/text, no session/CSRF;
  # the controller sets content-type + caching.
  scope "/", NewtonWeb do
    get "/sitemap.xml", SitemapController, :sitemap
    get "/robots.txt", SitemapController, :robots
  end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/newton_web/controllers/sitemap_controller_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add mix.exs mix.lock lib/newton_web/controllers/sitemap_controller.ex lib/newton_web/router.ex lib/newton_web.ex test/newton_web/controllers/sitemap_controller_test.exs
git commit -m "Serve a dynamic sitemap.xml and robots.txt"
```

(The `git rm` in Step 4 already staged the robots.txt deletion, so this commit includes it.)

---

### Task 2: Newton.Telemetry emission facade

**Files:**
- Create: `lib/newton/telemetry.ex`
- Test: `test/newton/telemetry_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces: `Newton.Telemetry.span(subsystem :: atom(), operation :: atom(), start_metadata :: map(), fun :: (-> {result, stop_metadata :: map()})) :: result` — emits `[:newton, subsystem, operation, :start | :stop | :exception]`. Task 3 calls `Newton.Telemetry.span(:indexnow, :submit, ...)`.

- [ ] **Step 1: Write the failing test**

Create `test/newton/telemetry_test.exs`:

```elixir
defmodule Newton.TelemetryTest do
  use ExUnit.Case, async: true

  test "span emits [:newton | suffix] start/stop events and returns the fun's result" do
    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:newton, :demo, :op, :start],
        [:newton, :demo, :op, :stop]
      ])

    result = Newton.Telemetry.span(:demo, :op, %{items: 2}, fn -> {:done, %{result: :ok}} end)

    assert result == :done
    assert_received {[:newton, :demo, :op, :start], ^ref, %{}, %{items: 2}}
    assert_received {[:newton, :demo, :op, :stop], ^ref, %{duration: _}, %{result: :ok}}
  end
end
```

(`:telemetry_test` ships with the `telemetry` package; handlers send `{event, ref, measurements, metadata}` to the test pid.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/newton/telemetry_test.exs`
Expected: FAIL — `Newton.Telemetry` is undefined.

- [ ] **Step 3: Implement the facade**

Create `lib/newton/telemetry.ex`:

```elixir
defmodule Newton.Telemetry do
  @moduledoc """
  Emission facade for app telemetry: owns the [:newton, ...] event prefix so
  event names stay consistent. App code emits through here, never via raw
  :telemetry calls.
  """

  @spec span(atom(), atom(), map(), (-> {result, map()})) :: result when result: term()
  def span(subsystem, operation, start_metadata, fun) do
    :telemetry.span([:newton, subsystem, operation], start_metadata, fun)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/newton/telemetry_test.exs`
Expected: 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/telemetry.ex test/newton/telemetry_test.exs
git commit -m "Add a Newton.Telemetry facade owning the event prefix"
```

---

### Task 3: Newton.IndexNow client, key file, config, supervisor, metrics

**Files:**
- Create: `lib/newton/index_now.ex`
- Create: `priv/static/d1258f1d59aea5c8f3e604eb494cc477.txt`
- Modify: `lib/newton_web.ex:20-22` (static_paths)
- Modify: `config/config.exs` (before the trailing `import_config`)
- Modify: `config/prod.exs` (append)
- Modify: `config/test.exs` (append)
- Modify: `lib/newton/application.ex:10-17` (children)
- Modify: `lib/newton_web/telemetry.ex` (metrics list, ~line 23)
- Test: `test/newton/index_now_test.exs`

**Interfaces:**
- Consumes: `Newton.Telemetry.span/4` (Task 2).
- Produces: `Newton.IndexNow.submit(urls :: [String.t()]) :: :ok | {:error, term()}` and the `Newton.TaskSupervisor` process. Task 4 calls both.

- [ ] **Step 1: Create the key file**

```bash
printf '%s' 'd1258f1d59aea5c8f3e604eb494cc477' > priv/static/d1258f1d59aea5c8f3e604eb494cc477.txt
```

In `lib/newton_web.ex`, append it to `static_paths`:

```elixir
  def static_paths,
    do:
      ~w(assets fonts images favicon.ico favicon.svg favicon-32.png favicon-96.png apple-touch-icon.png og-default.png og-links.png d1258f1d59aea5c8f3e604eb494cc477.txt)
```

- [ ] **Step 2: Add configuration**

`config/config.exs`, before the `import_config "#{config_env()}.exs"` line:

```elixir
config :newton, Newton.IndexNow,
  key: "d1258f1d59aea5c8f3e604eb494cc477",
  enabled: false
```

`config/prod.exs`, at the end:

```elixir
config :newton, Newton.IndexNow, enabled: true
```

`config/test.exs`, at the end:

```elixir
config :newton, Newton.IndexNow, req_options: [plug: {Req.Test, Newton.IndexNow}]
```

(Config keyword lists for the same key deep-merge across files, so prod/test override only what they set.)

- [ ] **Step 3: Add the Task.Supervisor**

In `lib/newton/application.ex`, add to `children` after the PubSub entry:

```elixir
      {Phoenix.PubSub, name: Newton.PubSub},
      {Task.Supervisor, name: Newton.TaskSupervisor},
```

- [ ] **Step 4: Write the failing tests**

Create `test/newton/index_now_test.exs`:

```elixir
defmodule Newton.IndexNowTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Newton.IndexNow

  @urls ["http://localhost:4002/posts/hello", "http://localhost:4002/posts"]

  defp enable do
    config = Application.get_env(:newton, IndexNow)
    Application.put_env(:newton, IndexNow, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, IndexNow, config) end)
  end

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :indexnow, :submit, :stop]])
    %{ref: ref}
  end

  test "submits host, key, and urlList to the API", %{ref: ref} do
    enable()
    test_pid = self()

    Req.Test.stub(IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    assert IndexNow.submit(@urls) == :ok

    assert_received {:request, request}
    assert request["host"] == "localhost"
    assert request["key"] == "d1258f1d59aea5c8f3e604eb494cc477"
    assert request["urlList"] == @urls

    assert_received {[:newton, :indexnow, :submit, :stop], ^ref, %{duration: _},
                     %{result: :ok, status: 200, url_count: 2}}
  end

  test "non-2xx responses return an error, log, and mark the span", %{ref: ref} do
    enable()
    Req.Test.stub(IndexNow, fn conn -> Plug.Conn.send_resp(conn, 422, "") end)

    log =
      capture_log(fn ->
        assert IndexNow.submit(@urls) == {:error, {:status, 422}}
      end)

    assert log =~ "IndexNow"

    assert_received {[:newton, :indexnow, :submit, :stop], ^ref, %{duration: _},
                     %{result: :error, status: 422, url_count: 2}}
  end

  test "no-ops when disabled", %{ref: ref} do
    assert IndexNow.submit(@urls) == :ok
    refute_received {[:newton, :indexnow, :submit, :stop], ^ref, _, _}
  end

  test "an empty url list is a no-op", %{ref: ref} do
    enable()
    assert IndexNow.submit([]) == :ok
    refute_received {[:newton, :indexnow, :submit, :stop], ^ref, _, _}
  end
end
```

(`async: false` because the tests mutate the app env; the file runs serially alongside Task 4's integration test, which does the same.)

- [ ] **Step 5: Run tests to verify they fail**

Run: `mix test test/newton/index_now_test.exs`
Expected: FAIL — `Newton.IndexNow` is undefined.

- [ ] **Step 6: Implement the client**

Create `lib/newton/index_now.ex`:

```elixir
defmodule Newton.IndexNow do
  @moduledoc """
  Submits changed public URLs to the IndexNow API so participating engines
  (Bing, Yandex, Seznam, Naver) recrawl promptly. Google does not participate;
  it discovers changes through the sitemap.
  """
  require Logger

  @endpoint "https://api.indexnow.org/indexnow"

  @spec submit([String.t()]) :: :ok | {:error, term()}
  def submit([]), do: :ok

  def submit(urls) do
    config = Application.get_env(:newton, __MODULE__, [])

    if config[:enabled] do
      do_submit(urls, config)
    else
      :ok
    end
  end

  defp do_submit(urls, config) do
    Newton.Telemetry.span(:indexnow, :submit, %{url_count: length(urls)}, fn ->
      body = %{host: URI.parse(hd(urls)).host, key: config[:key], urlList: urls}

      {outcome, status} =
        case Req.post(@endpoint, [json: body] ++ Keyword.get(config, :req_options, [])) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            {:ok, status}

          {:ok, %Req.Response{status: status}} ->
            Logger.warning("IndexNow rejected submission (status #{status}): #{inspect(urls)}")
            {{:error, {:status, status}}, status}

          {:error, reason} ->
            Logger.warning("IndexNow submission failed: #{inspect(reason)} urls: #{inspect(urls)}")
            {{:error, reason}, nil}
        end

      result = if outcome == :ok, do: :ok, else: :error
      {outcome, %{result: result, status: status, url_count: length(urls)}}
    end)
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/newton/index_now_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 8: Add the LiveDashboard metric**

In `lib/newton_web/telemetry.ex`, inside `def metrics do [` (before the Phoenix metrics group), add:

```elixir
      # IndexNow Metrics
      summary("newton.indexnow.submit.stop.duration",
        unit: {:native, :millisecond},
        tags: [:result]
      ),
```

- [ ] **Step 9: Run the full suite**

Run: `mix test`
Expected: 0 failures (the new supervisor child and config are inert for existing tests).

- [ ] **Step 10: Commit**

```bash
git add lib/newton/index_now.ex priv/static/d1258f1d59aea5c8f3e604eb494cc477.txt lib/newton_web.ex config/config.exs config/prod.exs config/test.exs lib/newton/application.ex lib/newton_web/telemetry.ex test/newton/index_now_test.exs
git commit -m "Add an IndexNow client with telemetry, gated to prod"
```

---

### Task 4: IndexNowNotifier + editor wiring + integration test

**Files:**
- Create: `lib/newton_web/index_now_notifier.ex`
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (alias ~line 11; functions at ~94, ~298, ~317, ~338, ~450, ~459, ~472)
- Test: `test/newton_web/index_now_notifier_test.exs`
- Test: `test/newton_web/live/admin/post_editor_index_now_test.exs`

**Interfaces:**
- Consumes: `Newton.IndexNow.submit/1` and `Newton.TaskSupervisor` (Task 3).
- Produces: `NewtonWeb.IndexNowNotifier.notify_change(before :: %Post{} | nil, after :: %Post{} | nil) :: :ok` and `changed_urls/2` (same signature, returns `[String.t()]`).

- [ ] **Step 1: Write the failing unit tests**

Create `test/newton_web/index_now_notifier_test.exs`:

```elixir
defmodule NewtonWeb.IndexNowNotifierTest do
  use ExUnit.Case, async: true
  use NewtonWeb, :verified_routes

  alias Newton.Blog.Post
  alias NewtonWeb.IndexNowNotifier

  @published %Post{slug: "hello", published_at: ~U[2026-07-01 12:00:00Z]}
  @draft %Post{slug: "hello", published_at: nil}

  test "draft-only mutations change nothing" do
    assert IndexNowNotifier.changed_urls(@draft, @draft) == []
    assert IndexNowNotifier.changed_urls(nil, @draft) == []
    assert IndexNowNotifier.changed_urls(@draft, nil) == []
    assert IndexNowNotifier.changed_urls(nil, nil) == []
  end

  test "publishing submits the post URL and the feed pages" do
    assert IndexNowNotifier.changed_urls(@draft, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert IndexNowNotifier.changed_urls(nil, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "editing a published post submits its URL once" do
    assert IndexNowNotifier.changed_urls(@published, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "a slug change submits the old and new URLs" do
    renamed = %Post{@published | slug: "renamed"}

    assert IndexNowNotifier.changed_urls(@published, renamed) ==
             [url(~p"/posts/hello"), url(~p"/posts/renamed"), url(~p"/"), url(~p"/posts")]
  end

  test "unpublishing and deleting submit the dead URL" do
    assert IndexNowNotifier.changed_urls(@published, @draft) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert IndexNowNotifier.changed_urls(@published, nil) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/newton_web/index_now_notifier_test.exs`
Expected: FAIL — `NewtonWeb.IndexNowNotifier` is undefined.

- [ ] **Step 3: Implement the notifier**

Create `lib/newton_web/index_now_notifier.ex`:

```elixir
defmodule NewtonWeb.IndexNowNotifier do
  @moduledoc """
  Computes which public URLs a post mutation changed and submits them to
  IndexNow off the request path. Draft-only mutations submit nothing.
  """
  use NewtonWeb, :verified_routes

  alias Newton.Blog.Post
  alias Newton.IndexNow

  @spec notify_change(%Post{} | nil, %Post{} | nil) :: :ok
  def notify_change(before_post, after_post) do
    case changed_urls(before_post, after_post) do
      [] ->
        :ok

      urls ->
        {:ok, _pid} = Task.Supervisor.start_child(Newton.TaskSupervisor, IndexNow, :submit, [urls])
        :ok
    end
  end

  @spec changed_urls(%Post{} | nil, %Post{} | nil) :: [String.t()]
  def changed_urls(before_post, after_post) do
    case post_urls(before_post) ++ post_urls(after_post) do
      [] -> []
      urls -> Enum.uniq(urls) ++ [url(~p"/"), url(~p"/posts")]
    end
  end

  defp post_urls(%Post{published_at: %DateTime{}, slug: slug}), do: [url(~p"/posts/#{slug}")]
  defp post_urls(_), do: []
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/index_now_notifier_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Wire the editor call sites**

In `lib/newton_web/live/admin/post_live/editor.ex`:

Add the alias after `alias NewtonWeb.Admin.Layouts` (~line 11):

```elixir
  alias NewtonWeb.IndexNowNotifier
```

**Site 1 — `handle_event("delete", ...)` (~line 297):** notify after the successful delete:

```elixir
  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)
    IndexNowNotifier.notify_change(socket.assigns.post, nil)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> push_navigate(to: ~p"/admin/posts")}
  end
```

**Site 2 — `ensure_post/1` create branch (~line 94):** add the notify line at the top of the `{:ok, post}` branch:

```elixir
      {:ok, post} ->
        IndexNowNotifier.notify_change(nil, post)

        socket
        |> assign(:post, post)
        |> assign(:published_at, post.published_at)
        |> assign(:editor_post_id, post.id)
        |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")
```

**Site 3 — `persist_autosave/3` create branch (~line 317):** add the notify line at the top of the `{:ok, post}` branch (the rest of the branch is unchanged):

```elixir
        {:ok, post} ->
          IndexNowNotifier.notify_change(nil, post)

          {:noreply,
           socket
```

**Site 4 — `persist_autosave/3` update branch (~line 337):** the result must not shadow the pre-mutation post; replace the whole function:

```elixir
  defp persist_autosave(socket, %Post{} = post, params) do
    case Blog.update_post(post, never_blank_identity(params, post)) do
      {:ok, updated} ->
        IndexNowNotifier.notify_change(post, updated)

        {:noreply,
         socket
         |> assign(:post, updated)
         |> assign(:autosave_params, nil)
         |> assign(:autosave_timer, nil)
         |> assign(:save_state, :saved)
         |> reoffer_identity(updated, params)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :save_state, :error)}
    end
  end
```

**Site 5 — `set_published/2` (~line 449):** replace the whole function:

```elixir
  defp set_published(socket, published_at) do
    before = socket.assigns.post
    {:ok, post} = Blog.update_post(before, %{"published_at" => published_at})
    IndexNowNotifier.notify_change(before, post)

    socket
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> put_flash(:info, if(post.published_at, do: "Post published", else: "Moved to draft"))
  end
```

(Keep the existing comment above the function.)

**Site 6 — `save/3` create branch (~line 459):** add the notify line at the top of the `{:ok, post}` branch:

```elixir
      {:ok, post} ->
        IndexNowNotifier.notify_change(nil, post)

        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}
```

**Site 7 — `save/3` update branch (~line 471):** replace the whole function (same shadowing rename as Site 4):

```elixir
  defp save(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, updated} ->
        IndexNowNotifier.notify_change(post, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> assign(:post, updated)
         |> assign(:published_at, updated.published_at)
         |> assign(:form, to_form(Blog.change_post(updated)))
         |> assign(:save_state, :saved)
         |> assign(:autosave_params, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
```

- [ ] **Step 6: Write the integration test**

Create `test/newton_web/live/admin/post_editor_index_now_test.exs`:

```elixir
defmodule NewtonWeb.Admin.PostEditorIndexNowTest do
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    config = Application.get_env(:newton, Newton.IndexNow)
    Application.put_env(:newton, Newton.IndexNow, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, Newton.IndexNow, config) end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  test "publishing a post submits its URL to IndexNow", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "IndexNow post",
        slug: "indexnow-post",
        body_markdown: "Hello."
      })

    test_pid = self()

    Req.Test.stub(Newton.IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:indexnow_request, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    render_click(view, "publish_now", %{})

    assert_receive {:indexnow_request, %{"urlList" => urls}}, 2_000
    assert url(~p"/posts/indexnow-post") in urls
    assert url(~p"/posts") in urls
  end
end
```

(Ownership note: `Req.Test.stub/2` registers under the test pid; the LiveView process and the `Task.Supervisor` child both inherit `$callers`, which `Req.Test` walks to find the stub — no explicit `allow` needed. `async: false` because the setup mutates app env, same as Task 3's file.)

- [ ] **Step 7: Run the new tests**

Run: `mix test test/newton_web/live/admin/post_editor_index_now_test.exs test/newton_web/index_now_notifier_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 8: Run the full editor suite**

Run: `mix test test/newton_web/live/admin/`
Expected: 0 failures — the notify calls are no-ops for drafts, so existing editor tests are unaffected.

- [ ] **Step 9: Run precommit**

Run: `mix precommit`
Expected: compile with no warnings, format clean, credo clean, all tests pass, pnpm tests pass, dialyzer clean. Fix anything it raises before committing.

- [ ] **Step 10: Commit**

```bash
git add lib/newton_web/index_now_notifier.ex lib/newton_web/live/admin/post_live/editor.ex test/newton_web/index_now_notifier_test.exs test/newton_web/live/admin/post_editor_index_now_test.exs
git commit -m "Notify IndexNow when a post's public URLs change"
```
