# Standard.site Support Design

**Goal:** Publish this site's posts as AT Protocol records per the
[standard.site](https://standard.site) lexicons, so ATmosphere users can follow
jamesnewton.com like any Bluesky account and discover posts natively.

**Context:** standard.site defines two record types living in the author's PDS
repo (the Bluesky account's data store): `site.standard.publication` (the
site) and `site.standard.document` (each post). The site proves ownership via
a `.well-known` endpoint and per-page link tags; the AppView crawls and
verifies. James's account: handle `jamesnewton.com`, DID
`did:plc:engjedcb3kwfl4vuo5gtr6n4` (DNS TXT verified — the app serves no
`/.well-known/atproto-did` and doesn't need to).

## Decisions

- **Metadata-only documents** (James chose): `site`, `title`, `path`,
  `publishedAt`, `description` (excerpt). Readers click through to the site;
  no content-sync drift. Full content is a compatible later upgrade.
- **`showInDiscover: true`** (James chose) on the publication record.
- **Record key = post slug.** Slugs already satisfy rkey rules
  (`[A-Za-z0-9._:~-]`, ≤512), making every document AT-URI computable —
  `at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.document/<slug>` — with
  no schema changes and no stored URIs. A slug change is a delete+put (old
  rkey removed, new rkey created), exactly parallel to IndexNow's old/new URL
  submission.
- **One notifier seam, two consumers.** The editor's seven mutation call sites
  currently call `NewtonWeb.IndexNowNotifier.notify_change/2`. That module is
  generalized into `NewtonWeb.PublicationNotifier`: it computes the
  publish-state transition once and fans out to IndexNow (changed URLs) and
  Standard (record put/delete). The IndexNow URL-set logic moves inside
  unchanged; every existing IndexNow test must stay green (renamed module
  aside) — that is the proof the refactor is behavior-preserving. Future
  syndication targets plug into this seam.
- **Session-per-call, no token caching.** `com.atproto.server.createSession`
  before each `putRecord`/`deleteRecord` — at blog publish volume (a few calls
  a week) token caching is machinery without a payoff.
- **Prod-gated until domain cutover, like IndexNow.** The publication URL is
  `https://jamesnewton.com`, which does not serve this app yet; AppView
  verification cannot complete until DNS points here. `enabled: false`
  everywhere until launch. The launch steps live in `docs/production.md`.

## Components

### 1. `Newton.Standard` (client, `lib/newton/standard.ex`)

Sibling of `Newton.IndexNow`. Config under `config :newton, Newton.Standard`:

- `enabled:` `false` in all envs today; flipped in prod at launch
- `identifier:` `"jamesnewton.com"` (login handle)
- `did:` `"did:plc:engjedcb3kwfl4vuo5gtr6n4"`
- `pds_url:` `"https://bsky.social"`
- `publication_uri:` set after the one-time mix task (nil until then)
- `app_password:` from `BSKY_APP_PASSWORD` (Fly secret, read in
  `runtime.exs` when enabled)
- `req_options:` test injects `plug: {Req.Test, Newton.Standard}`

API (all no-op `:ok` when disabled; each wraps its HTTP work in
`Newton.Telemetry.span(:standard, :sync, ...)` with bounded metadata —
`operation:` `:put_document | :delete_document | :put_publication`, `result:`,
HTTP status; record contents and slugs stay out of metric dimensions):

```elixir
@spec put_document(%Post{}) :: :ok | {:error, term()}
# createSession → com.atproto.repo.putRecord
#   repo: did, collection: "site.standard.document", rkey: post.slug,
#   record: %{"$type" => "site.standard.document",
#             "site" => publication_uri, "title" => post.title,
#             "path" => "/posts/#{post.slug}",
#             "publishedAt" => DateTime.to_iso8601(post.published_at),
#             "description" => post.excerpt}

@spec delete_document(String.t()) :: :ok | {:error, term()}
# createSession → com.atproto.repo.deleteRecord for the slug rkey

@spec put_publication() :: {:ok, String.t()} | {:error, term()}
# createSession → putRecord (collection "site.standard.publication",
# rkey "self"): %{"$type" => ..., "url" => "https://jamesnewton.com",
# "name" => "James Newton", "description" => "Software & Photography",
# "preferences" => %{"showInDiscover" => true}}
# Returns the record AT-URI for config/.well-known.
```

Failures log a warning (slugs allowed in logs, never in metrics) and return
`{:error, ...}`; callers fire-and-forget.

### 2. `NewtonWeb.PublicationNotifier` (rename + fan-out)

`lib/newton_web/index_now_notifier.ex` → `lib/newton_web/publication_notifier.ex`.
Public seam unchanged in shape: `notify_change(before :: %Post{} | nil,
after :: %Post{} | nil) :: :ok`. Internally computes the transition once:

| Transition | IndexNow (existing) | Standard (new) |
|---|---|---|
| draft-only mutations | nothing | nothing |
| publish / create-published | URLs | `put_document(post)` |
| published edit, same slug | URLs | `put_document(post)` |
| published slug change | old+new URLs | `delete_document(old)` + `put_document(post)` |
| unpublish | old URL | `delete_document(slug)` |
| delete published | old URL | `delete_document(slug)` |

Each side dispatches via `Task.Supervisor.start_child(Newton.TaskSupervisor, ...)`
(separate tasks — one integration failing must not starve the other), with the
existing log-on-`start_child`-error guard. The editor's seven call sites are
renamed calls only. Existing IndexNow URL-set unit tests carry over against
the new module name; existing editor integration tests must pass unmodified
except the module rename.

### 3. Verification surface

- Router (existing crawler scope, no `:browser` pipeline):
  `get "/.well-known/site.standard.publication", StandardController, :publication`
  — plain text `publication_uri`; 404 when unset.
- `root.html.heex` head: site-wide
  `<link rel="site.standard.publication" href={publication AT-URI}>` (rendered
  only when configured), and on published post pages
  `<link rel="site.standard.document" href={document AT-URI}>` — driven by an
  optional `@standard_document` assign set in `PostController.show/2` for the
  published branch only. Previews and drafts never render it.

### 4. `mix standard.put_publication` (one-time task)

Requires `BSKY_APP_PASSWORD` in the environment; calls
`Newton.Standard.put_publication/0` bypassing the `enabled` gate (explicit
operator action), prints the AT-URI and the config line to add. Idempotent —
rkey `"self"` putRecord upserts.

### 5. Launch checklist

Lives in `docs/production.md` (created alongside this spec): DNS/certs,
`PHX_HOST`, the WebAuthn `rp_id` passkey consequence, enabling IndexNow and
Standard, Search Console, and post-cutover verification.

## Out of scope

- Full-content documents (compatible upgrade later).
- Subscriptions/recommend graph lexicons (reader-side; nothing to serve).
- OAuth (app password is the established pattern for server-side XRPC today).
- Backfilling: the two existing published posts get records via the normal
  editor path (touch-save each) or a one-off IEx `put_document/1` call at
  launch — not worth a mix task.

## Error handling

- Disabled → all client calls return `:ok` without HTTP.
- PDS/network failures → warning log, `{:error, ...}`, swallowed by the
  fire-and-forget task; publishing UX never blocks (IndexNow precedent).
- `publication_uri` unset while enabled → `put_document` refuses with a logged
  error (records must reference the publication; misconfiguration should be
  loud in logs, silent in UX).
- The `.well-known` route is total: 404 (unset) or 200 text.

## Testing

1. **Client (`Req.Test`):** session→putRecord flow asserting repo/collection/
   rkey/record body (metadata-only shape, ISO8601 publishedAt); delete flow;
   publication record body incl. `showInDiscover`; disabled no-op;
   unset-publication_uri refusal; non-2xx and transport errors return
   `{:error, ...}` and log; telemetry span with bounded metadata.
2. **Notifier:** transition table above, asserting which Standard calls fire
   (slug change = delete old + put new); existing IndexNow assertions
   unchanged. Fan-out isolation: a Standard-side failure doesn't suppress the
   IndexNow submission (and vice versa).
3. **Editor integration:** publishing through the LiveView produces a stubbed
   putRecord whose rkey is the post slug (Req.Test + enabled override,
   IndexNow-test pattern).
4. **Verification surface:** `.well-known` 200/404 behavior; document link tag
   present on a published post page with the computed AT-URI, absent on
   preview-token pages and the home page.
