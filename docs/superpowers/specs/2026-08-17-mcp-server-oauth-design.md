# MCP server with OAuth 2.1: agents reading posts directly

Give agents (Claude Code, claude.ai connectors) an authenticated MCP endpoint
on jamesnewton.com that reads posts — drafts included — replacing preview
links, whose caching in agent harnesses has proven unreliable.

## Decision summary

- **Clients served:** claude.ai custom connectors and Claude Code both speak
  the MCP authorization flow, so OAuth 2.1 is the single auth path. No bearer
  side-channel.
- **Protocol layer:** `anubis_mcp ~> 2.0` (maintained fork of hermes_mcp;
  hermes upstream deleted, frozen at 0.14.1) handles streamable HTTP
  transport, sessions, and version negotiation; we write only tool modules
  and the token validator.
- **OAuth layer:** hand-rolled single-user subset. Elixir OAuth-provider
  libraries (boruta, ex_oauth2_provider) are heavyweight or predate
  OAuth 2.1/DCR; for one user the subset is less code than their config.
- **Tool surface:** read-only — `list_posts` and `read_post`. No write tools.

## Architecture

| Unit | Responsibility |
|---|---|
| `Newton.OAuth` (domain) | Clients, grants, tokens: registration, code issuance, PKCE verification, token exchange/rotation, bearer verification. All hashing and expiry logic. |
| OAuth web layer | Four endpoints (metadata ×2, register, authorize+token) plus the consent page. Thin: parameter validation and rendering; rules live in `Newton.OAuth`. |
| MCP server | `anubis_mcp` mounted at `/mcp`, authorizing every request via `Newton.MCP.TokenValidator`; tool modules call `Newton.Blog`. |

`Newton.MCP.TokenValidator` resolves `Authorization: Bearer <token>` via
`Newton.OAuth` before anubis dispatches the request to a tool. `/mcp` lives
outside the browser pipeline — no session, no CSRF. Anubis's own transport
serves `GET /.well-known/oauth-protected-resource` and emits 401 +
`WWW-Authenticate` on missing/invalid bearer, replacing the hand-written
bearer plug and metadata endpoint this spec originally assumed.

## Data model

**`oauth_clients`** — created only via dynamic client registration:
- `client_id` (random, indexed), `client_secret_hash` (nullable — public
  clients use PKCE only), `client_name`
- `redirect_uris` (array of strings) — stored exactly as registered, matched
  exactly at authorize/token time; no wildcards, no prefix matching
- `token_endpoint_auth_method`: `none` | `client_secret_post` | `client_secret_basic`

**`oauth_grants`** — one row per grant lifecycle (code → access + refresh are
phases of one grant):
- authorization-code phase: `code_hash`, `code_expires_at`, `code_challenge`
  (S256 only), `redirect_uri`, `resource`, `code_used_at`
- token phase: `access_token_hash`, `access_token_expires_at`,
  `refresh_token_hash`, `refresh_token_expires_at`, `revoked_at`
- `client_id` FK

All secrets (codes, access tokens, refresh tokens, client secrets) are random
32-byte values, stored SHA-256 hashed — the same posture as session tokens.
Single-user site: every token acts as the site owner; no `user_id` until a
second user exists.

## OAuth endpoints and their security requirements

**`GET /.well-known/oauth-authorization-server`** (RFC 8414): static JSON
built from the endpoint URL. `grant_types_supported`:
`["authorization_code", "refresh_token"]`; `code_challenge_methods_supported`:
`["S256"]`.

**`GET /.well-known/oauth-protected-resource`** (RFC 9728): served by
anubis's own transport (`Anubis.Server.Transport.WellKnown`), not a
hand-written endpoint. 401 responses from `/mcp` also come from anubis's
transport, via `Newton.MCP.TokenValidator`, carrying
`WWW-Authenticate: Bearer resource_metadata="…"` so clients discover the flow
(MCP authorization spec).

**`POST /oauth/register`** (RFC 7591): open registration, as claude.ai
requires. Validates every `redirect_uri` is absolute `https://` (exception:
`http://127.0.0.1`/`http://localhost` loopback for local CLI clients).
Returns `client_id` (+ `client_secret` once, when the method needs one).

**`GET/POST /oauth/authorize`** — lives in a dedicated
`[:browser, :require_authenticated_user, :require_sudo_mode]` scope: only a
logged-in admin who has re-authenticated within the last 10 minutes can
approve a grant.
- `code_challenge` required, method `S256` only; `plain` and absent → error
- `redirect_uri` must exactly match a registered URI; on mismatch render an
  error page — never redirect to an unregistered URI
- `state` echoed verbatim on the redirect
- Consent is a CSRF-protected POST showing `client_name` and redirect host
- Approval issues a single-use code: 5-minute expiry, bound to
  client_id + redirect_uri + code_challenge + `resource` (RFC 8707)

**`POST /oauth/token`** — grants `authorization_code` and `refresh_token`
only. No implicit, password, or client_credentials.
- Client auth per registered method; `none` clients rely on PKCE
- PKCE verified `S256(verifier) == challenge` in constant time
- `redirect_uri` must match the code's; code must be unused and unexpired
- **Code reuse revokes the entire grant** (OAuth 2.1)
- Access token: opaque, 1-hour expiry. Refresh token: rotated on every
  use; **reuse of a rotated refresh token revokes the grant family**;
  30-day absolute expiry

**Bearer validation at `/mcp`:** hashed lookup, expiry check, and audience
check — the token's `resource` must equal the canonical MCP URL (the MCP
spec's token-audience/passthrough rule), all via `Newton.MCP.TokenValidator`.
Failures → 401 with `WWW-Authenticate` as above.

## MCP server

- Dep: `anubis_mcp ~> 2.0`, version pinned at plan time from hex
- Mounted at `/mcp`; every request is authorized by
  `Newton.MCP.TokenValidator`, configured on `Newton.MCP.Server`'s
  transport — no separate hand-written bearer plug
- Tools:
  - `list_posts(status: "all" | "draft" | "published", default "all")` →
    rows of slug, title, status, updated_at. Maps onto `Blog.list_posts/1`.
  - `read_post(slug)` → title, status, excerpt, markdown body. Drafts
    included — that is the feature.
- Unknown slug → MCP tool error ("no post with slug …"), never a raise
- Telemetry: `[:newton, :mcp, :tool_call]` span, metadata bounded to tool
  name and result class; wired into `Newton.Metrics.definitions/0`
- CORS: anubis emits no CORS headers, and `/mcp` uses header-based (not
  cookie) auth, so browser-origin JS can neither read the response nor
  forge an authenticated request. Browser-based MCP clients are
  unsupported by design — do not add a permissive CORS plug.

## Error handling

- OAuth endpoints return RFC 6749 error JSON (`invalid_request`,
  `invalid_grant`, `invalid_client`, `unauthorized_client`,
  `unsupported_grant_type`) with correct HTTP statuses
- Authorize-time validation failures that can safely redirect do (with
  `error` + `state`); redirect_uri problems never redirect
- The MCP layer never 500s on bad tool input — anubis returns tool errors

## Testing

**OAuth integration (ConnCase):**
- Happy path: register → authorize (logged-in admin, consent POST) → code
  exchange → authenticated `/mcp` call succeeds
- Attack table, each expecting the specified failure:
  wrong PKCE verifier · reused code (and grant revoked after) · expired code ·
  redirect_uri mismatch at authorize · redirect_uri mismatch at token ·
  unregistered redirect_uri · missing/plain code_challenge · expired access
  token · reused rotated refresh token (family revoked) · token whose
  `resource` is not the MCP URL · unauthenticated authorize → login redirect
- Metadata endpoints return spec-required fields

**MCP (anubis test harness):**
- `list_posts` includes drafts; status filter works
- `read_post` returns markdown body for a draft
- Unknown slug → tool error, not a crash
- Missing/invalid bearer → 401 with `WWW-Authenticate`

## Out of scope (deliberate)

Scopes/granular permissions, token revocation endpoint, registration rate
limiting, write tools, multi-user token ownership.

## Accepted risks

**Refresh-token reuse detection is one generation deep.** Rotation keeps the
current token hash plus the immediately-previous one; replaying that previous
token revokes the grant family (RFC 9700 theft signal). A replay of an
older-than-previous token is rejected for access — it no longer matches the
current hash — but does not proactively revoke the family. Since no
older token grants access, the residual is a missed alarm, not an access
leak; accepted for a single-user deployment. Closing it fully would mean
tracking every retired hash per grant.
