# standard.site: publishing to the ATmosphere

How jamesnewton.com announces itself and its posts to AT Protocol apps, and
what has to be true for that to work.

## What gets published

Two record types, written into the author's own PDS repo (Bluesky's
`bsky.social`), never to a service of ours:

**`site.standard.publication`** — one record, at `rkey: "self"`, describing the
site: its URL, name, description, and whether it opts into discovery. Written
once by an operator, not by the app.

**`site.standard.document`** — one record per published post, at `rkey: <slug>`,
carrying the post's title, path, published date, and excerpt. Each points back
at the publication record through its `site` field.

Both are **metadata only**. No post body ever leaves the machine; readers follow
the canonical URL back to the site. That is why a document record is a handful
of fields rather than a copy of the article.

## Architecture

| Module | Layer | Responsibility |
|---|---|---|
| `Newton.Standard` | domain | Transport. Authenticates against the PDS and writes/deletes records over XRPC. |
| `NewtonWeb.PublicationNotifier` | web | Diffs a post's before/after state into record operations, then spawns them. |
| `NewtonWeb.StandardController` | web | Serves `/.well-known/site.standard.publication`, the pointer AppViews verify against. |
| `Mix.Tasks.Standard.PutPublication` | mix | One-time operator action that creates the publication record. |

Every write authenticates first: `com.atproto.server.createSession` exchanges
the identifier and app password for a bearer token, which then authorizes a
`com.atproto.repo.putRecord` or `deleteRecord` call. Sessions are not cached —
each operation logs in again, which is fine at this volume and keeps the module
stateless.

**Fire-and-forget.** Operations run under `Newton.TaskSupervisor`, so a slow or
failing PDS can never block or crash the admin editor. Failures are logged
warnings, never raises.

## Configuration and enabling

Configured in two places, and both must line up.

**`config/config.exs`** holds the identity — committed, not secret:

```elixir
config :newton, Newton.Standard,
  enabled: false,
  identifier: "jamesnewton.com",
  did: "did:plc:engjedcb3kwfl4vuo5gtr6n4",
  pds_url: "https://bsky.social",
  publication_uri: "at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.publication/self"
```

**`config/runtime.exs`** reads the credential from the environment:

```elixir
config :newton, Newton.Standard, app_password: System.get_env("BSKY_APP_PASSWORD")
```

Use a Bluesky **app password**, never the account password. In production it is
a Fly secret:

```bash
fly secrets set BSKY_APP_PASSWORD=<app password>
```

### What `enabled` actually gates

`enabled: true` turns on **per-post publishing only** — `put_document/1` and
`delete_document/1` return `:ok` without an HTTP call when it is false, so the
notifier still runs end to end while nothing leaves the machine. That is the
dev and test posture.

Two things it does **not** gate, which is a common source of confusion:

- **`mix standard.put_publication` ignores it entirely.** The task is an
  explicit operator action; it runs whether the flag is on or off, and running
  it does not switch per-post publishing on.
- **`/.well-known/site.standard.publication` ignores it too.** The endpoint
  serves `publication_uri` straight from compile-time config, so it answers even
  with the flag off.

### Enabling, in order

1. Set `BSKY_APP_PASSWORD` as a Fly secret (above).
2. Run `mix standard.put_publication` **locally** — see below.
3. Flip `enabled: true` in `config/prod.exs` and deploy.
4. Backfill records for posts published before the flag went on (below).

Order matters because every document record points at the publication record
through its `site` field. Publishing documents first leaves them pointing at
something that does not exist. Nothing in the code checks for this — the guard
only catches a missing `publication_uri`, not a missing remote record.

The publication record hardcodes `https://jamesnewton.com`, so run this after
the domain points at the app, not before.

## `mix standard.put_publication`

Creates or updates the publication record.

```bash
BSKY_APP_PASSWORD=<app password> mix standard.put_publication
# publication record: at://did:plc:.../site.standard.publication/self
```

**Run it locally.** It talks only to `bsky.social` — no database, no endpoint,
no host lookup. The record it writes is a hardcoded literal, so the result is
identical wherever it runs. Running it in production would be harder for no
benefit: the release ships `/app/bin/newton` with `eval`/`rpc`, not Mix, so the
task is not even available there.

It is **idempotent** — `rkey: "self"` upserts — so re-running overwrites the
same record. Safe to repeat if you are unsure it took.

It raises if `BSKY_APP_PASSWORD` is unset, and raises on a failed write rather
than exiting quietly.

## Backfilling already-published posts

Records are written on post mutations, so anything published before `enabled`
went true has no document record. Either touch-save each post in the editor, or
from a production shell:

```bash
fly ssh console -C '/app/bin/newton rpc "
  Newton.Blog.list_published_posts()
  |> Enum.each(&Newton.Standard.put_document(Newton.Blog.get_post!(&1.id)))
"'
```

`put_document/1` no-ops when `enabled` is false, so this must run after step 3.

## Post lifecycle → what gets written

`PublicationNotifier.operations/2` diffs the before/after post:

| Transition | Operation |
|---|---|
| create draft, edit draft, delete draft | *nothing* |
| **publish** | `put_document` |
| **edit published, same slug** | `put_document` (upsert at the same rkey) |
| **rename published** (slug change) | `delete_document` (old slug) then `put_document` (new) |
| **unpublish** / **delete published** | `delete_document` |

Drafts never produce records, so preview-token URLs are never announced.

**Known wrinkle:** a slug rename issues the delete and the put as independent
fire-and-forget tasks. If the delete fails, the old record lingers in the PDS
until removed by hand. Accepted as best-effort cleanup.

## Verifying

```bash
# the pointer AppViews verify against
curl https://jamesnewton.com/.well-known/site.standard.publication
# → at://did:plc:.../site.standard.publication/self

# a post page carries the document link tag in its head
curl -s https://jamesnewton.com/posts/<slug> | grep site.standard.document
```

Domain-handle verification depends on the `_atproto` TXT record in DNS, which
ties `jamesnewton.com` to the DID above. Do not remove it — the publication
record and every document under it hang off that identity.
