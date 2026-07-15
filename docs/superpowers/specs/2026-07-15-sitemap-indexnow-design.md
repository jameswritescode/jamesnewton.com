# Sitemap + IndexNow Design

**Goal:** Serve a standards-compliant `sitemap.xml` for the public site, reference it from a dynamic `robots.txt`, and notify IndexNow-participating search engines (Bing, Yandex, Seznam, Naver) automatically when published content changes.

**Context:** phoenix_seo 0.3.0-rc is already adopted (canonical URLs, og/twitter meta, JSON-LD). It has no sitemap support. The classic "ping Google/Bing with the sitemap URL" mechanism is dead — Google removed its ping endpoint in January 2024, Bing likewise — so IndexNow-on-publish is the modern replacement, plus a one-time manual sitemap submission in Google Search Console (Google does not participate in IndexNow).

## Decisions

- **XML via `xml_builder` (~> 2.4)**, not raw IO lists — correct escaping for titles containing `&`/`<`, and the upcoming Atom/RSS feed will reuse the same dependency and pattern. `atomex` rejected (dormant since 2022); `saxy` rejected (parser with a struct encoder, wrong ergonomics for document building).
- **Dynamic sitemap, not build-time** — posts publish at runtime from the admin; a static file would go stale and break on multi-machine Fly deploys.
- **No `changefreq`/`priority`** — ignored by Google; noise.
- **`lastmod` on post entries only**, from `updated_at`, date-only ISO 8601 (`2026-07-15`). Static pages carry no lastmod rather than a fabricated one.
- **Dynamic `robots.txt`** — the `Sitemap:` directive needs an absolute URL matching the serving host; a static file can't know its host, and a fly.dev robots.txt pointing at jamesnewton.com is a cross-host reference. Serving it from the controller makes it correct on every host.
- **IndexNow triggers live in the web layer** (`PostLive.Editor`), not the Blog context — URLs are web-layer knowledge; `Newton.Blog` must not reach into `NewtonWeb`. All post mutations already funnel through the editor LiveView, so it is a single trigger surface.
- **Fire-and-forget submission** via `Task.Supervisor` — publishing must never block or crash on a slow/failing ping. Failures log a warning.
- **Telemetry** per AGENTS.md observability guidelines: the IndexNow client wraps its HTTP call in a telemetry span; metadata is bounded (result, HTTP status, URL count) — never the URLs themselves.
- **Emission goes through a thin app-owned facade, `Newton.Telemetry`**, not raw `:telemetry.span/3` at call sites. Surveyed alternatives: `telemetry_decorator` (dormant since 2022), OpenTelemetry stack / `o11y` (solves distributed tracing exported to a backend — no trace backend exists here, so it's ceremony shipping spans nowhere), `prom_ex` (metrics export, orthogonal). The facade owns the `[:newton, ...]` event prefix and the `{result, stop_metadata}` tuple contract in one place; every future instrumented feature reuses it. If real tracing with a backend ever lands, OpenTelemetry is the graduation path.

## Components

### 1. `NewtonWeb.SitemapController`

Routes, in a pipeline-less scope (same pattern as `/og` — no session/CSRF; controller sets content-type and caching):

```elixir
scope "/", NewtonWeb do
  get "/sitemap.xml", SitemapController, :sitemap
  get "/robots.txt", SitemapController, :robots
end
```

`robots.txt` is removed from `static_paths` in `lib/newton_web.ex` (Plug.Static would shadow the route) and `priv/static/robots.txt` is deleted.

**`:sitemap`** builds entries:

- Static pages, no lastmod: `/`, `/posts`, `/reading`, `/photos`, `/links`, `/resume`
- One entry per `Blog.list_published_posts()` post: `loc` = `url(~p"/posts/#{post.slug}")`, `lastmod` = `Date.to_iso8601(DateTime.to_date(post.updated_at))`

Rendered with `XmlBuilder.generate/1` from element tuples under `{:urlset, %{xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9"}, entries}`, served with content-type `application/xml` and `cache-control: public, max-age=3600` (matching the og image endpoint).

**`:robots`** renders plaintext:

```
User-agent: *
Disallow:

Sitemap: <url(~p"/sitemap.xml")>
```

Content-type `text/plain`, same cache-control. Admin/login need no Disallow entries — they are auth-gated and every public page already controls indexing via its robots meta tag; listing private paths in robots.txt only advertises them.

### 2. `Newton.Telemetry` (emission facade)

```elixir
Newton.Telemetry.span(subsystem :: atom(), operation :: atom(), start_meta :: map(), fun)
```

- Delegates to `:telemetry.span([:newton, subsystem, operation], start_meta, fun)`; `fun` returns `{result, stop_meta}` and `span/4` returns `result`.
- The single place that knows the `[:newton, ...]` prefix, keeping event names consistent with the AGENTS.md convention.
- New emitters (the upcoming Atom feed, future integrations) use this module; raw `:telemetry` calls in app code are a review smell.

### 3. `Newton.IndexNow` (client)

```elixir
Newton.IndexNow.submit([url, ...]) :: :ok | {:error, term()}
```

- POSTs `%{host: host, key: key, urlList: urls}` as JSON to `https://api.indexnow.org/indexnow` via Req. `host` is derived from the first URL; `key` from config.
- Config under `config :newton, Newton.IndexNow`:
  - `key:` the IndexNow key (same value as the key file)
  - `enabled:` `true` only in prod (`config/prod.exs`); `false` in dev/test. When disabled, `submit/1` returns `:ok` without an HTTP call.
  - `req_options:` merged into the Req request — test injects `plug: {Req.Test, Newton.IndexNow}`.
- Wraps the HTTP call in `Newton.Telemetry.span(:indexnow, :submit, ...)` (event `[:newton, :indexnow, :submit]`). Span metadata: `%{url_count: n}` on start; `%{result: :ok | :error, status: integer | nil, url_count: n}` on stop. No URLs in metadata.
- Any non-2xx status or transport error returns `{:error, ...}` and logs a warning with the status/reason (URLs may appear in the *log message* — logs are fine for unbounded values, metrics are not).

**Key file:** a one-time generated 32-hex-char key committed as `priv/static/<key>.txt` containing exactly the key, with `<key>.txt` added to `static_paths`. The key is public by design (engines verify ownership by fetching it from our host), so committing it is safe. The same literal goes in `config/config.exs`.

### 4. `NewtonWeb.IndexNowNotifier` (trigger + URL delta)

```elixir
NewtonWeb.IndexNowNotifier.notify_change(before :: %Post{} | nil, after :: %Post{} | nil) :: :ok
```

Computes the changed-URL set from before/after post states and submits it through `Task.Supervisor.start_child(Newton.TaskSupervisor, ...)`:

| Transition | URLs submitted |
|---|---|
| draft → draft (any edit), draft created, draft deleted | none |
| draft → published, or created already-published | post URL, `/`, `/posts` |
| published → published (edit, same slug) | post URL, `/`, `/posts` |
| published → published (slug change) | old post URL, new post URL, `/`, `/posts` |
| published → draft (unpublish) | old post URL, `/`, `/posts` |
| published deleted | old post URL, `/`, `/posts` |

`/` and `/posts` are included because both render the published-post feed. `nil` before = create; `nil` after = delete. When the computed set is empty, no task is spawned.

`{Task.Supervisor, name: Newton.TaskSupervisor}` is added to the application supervision tree.

**Call sites** — after each successful mutation in `PostLive.Editor` (create at lines ~94/317/459, update at ~338/450/472, delete at ~298), passing the pre-mutation post (or `nil`) and the result post (or `nil`). The publish/unpublish toggle (~450) is the highest-value trigger.

### 5. Telemetry metrics

`NewtonWeb.Telemetry.metrics/0` gains:

```elixir
summary("newton.indexnow.submit.stop.duration",
  unit: {:native, :millisecond},
  tags: [:result]
)
```

### 6. AGENTS.md

Already updated (Observability & telemetry section) — no further doc work in this project.

## Out of scope

- Atom/RSS feed — next project, will reuse `xml_builder`.
- Google Search Console API submission — one-time manual submission instead; resubmitting programmatically adds ceremony (GCP service account, secrets) for negligible crawl benefit.
- Sitemap index files / chunking — the protocol allows 50,000 URLs per file; this site has ~dozens.
- Gallery/photo detail pages — no public per-photo URLs exist today.

## Error handling

- Sitemap/robots: no failure modes beyond the DB query; standard Phoenix error handling applies.
- IndexNow: disabled config → silent no-op; HTTP failure → warning log + `{:error, ...}` from the client, swallowed by the fire-and-forget task; the admin UX never sees it. Task crashes are isolated by the supervisor.

## Testing

Behavior-focused (per test guidelines — no asserting on static markup):

1. **Sitemap controller:** a published post appears with `loc` and date-only `lastmod`; a draft post does not appear; response content-type is `application/xml`; all six static paths present.
2. **Robots controller:** response contains `Sitemap: <host>/sitemap.xml` for the request host; content-type `text/plain`.
3. **IndexNow client** (via `Req.Test`): posts key + host + urlList to the API; returns `{:error, ...}` and logs on non-2xx; emits the telemetry span (assert via `:telemetry_test.attach_event_handlers/2`); no-ops when disabled.
4. **Notifier deltas:** unit-test `notify_change/2` URL-set computation for each transition row above (pure function extracted so it tests without tasks/HTTP).
5. **Editor integration:** publishing a post through the editor LiveView triggers a submission containing the post URL (Req.Test stub + enabled-in-test override, or assert on the telemetry event).
