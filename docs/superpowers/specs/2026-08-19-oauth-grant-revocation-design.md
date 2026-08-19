# Admin settings: OAuth grant revocation

A "Connected apps" section on `/admin/settings` showing which OAuth clients
hold live access to the site's MCP endpoint, with per-client revocation.
Closes the operator-visibility gap flagged in the OAuth server's final
review: until now, answering "what has access to my drafts" required a
production console.

## Decision summary

- **Granularity is per-client.** One app can hold several grants (re-auths,
  multiple machines); the section lists clients with at least one active
  grant, and Revoke kills all of that client's active grants at once.
- **Revocation does not delete the client registration.** A revoked client
  keeps its DCR record; reconnecting still requires a fresh consent +
  sudo pass, so revoke genuinely means revoked while re-connection stays
  cheap.
- **Sudo-guarded like the passkey actions.** The section lives on the
  already sudo-gated settings page, and the revoke event re-checks sudo
  freshness at event time via the existing `with_fresh_sudo` pattern.

## Domain (`Newton.OAuth`)

**`list_authorized_clients/0`** — clients having ≥1 active grant, where
active means `revoked_at` is nil AND (access token unexpired OR refresh
token unexpired). Returns, per client:

- the `%Client{}` (name is what the UI shows)
- `first_connected_at` — earliest active grant's `inserted_at`
- `last_active_at` — latest active grant's `updated_at` (refresh rotation
  touches `updated_at`, so this honestly tracks last use)
- `grant_count` — number of active grants

Ordered by `last_active_at` descending. Clients with zero active grants do
not appear.

**`revoke_client_grants/1`** — takes a `%Client{}` (or client id), sets
`revoked_at` on all its active grants in one `update_all`, returns the
revoked count. Wrapped in the existing `[:newton, :oauth, :grant]`
telemetry span with metadata `%{operation: :admin_revoke, result: :ok}` —
bounded values only, consistent with the module's other spans.

After revocation, every access and refresh token belonging to those grants
must fail verification/refresh (this falls out of the existing
`revoked_at` checks; the tests pin it).

## UI (`NewtonWeb.Admin.SettingsLive`)

A "Connected apps" section after Recovery codes:

- Assign `:authorized_clients` at mount from `list_authorized_clients/0`.
- Row per client, mirroring the passkey list styling: client name, then
  "First connected {date} · Last active {date} · {n} grant(s)" in the
  subtle text style, and a secondary **Revoke** button with
  `data-confirm`.
- The revoke event runs inside `with_fresh_sudo` (same as
  `delete_passkey`), then re-assigns the list and flashes
  "{client name} revoked."
- Empty state (always-rendered section): "No apps have access."
- Dates render via the page's existing `format_day/1`.

## Error handling

Revoking a client that has no active grants (raced by expiry or a
double-click) is a no-op: re-assign the list, no crash, no error flash.

## Testing

Context (`Newton.OAuthTest`):
- listing includes a client with an active grant, with correct aggregates
  across multiple grants
- listing excludes clients whose grants are all revoked, and clients whose
  grants are fully expired (access AND refresh past expiry)
- revoke kills every active grant; a previously-verifying access token
  fails `verify_access_token/1` and its refresh token fails `refresh/2`
- revoking a grantless client returns 0 and does not raise

LiveView (settings tests):
- the section lists a connected client's name
- clicking Revoke removes the row and the client's token no longer
  verifies
- with stale sudo, the revoke event redirects to confirm-access and
  revokes nothing

## Out of scope (deliberate)

Per-grant rows, client-registration deletion/pruning, a token revocation
endpoint (RFC 7009), and any surface for inspecting individual tokens.
