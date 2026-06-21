# Passkey Authentication + Account Settings — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Add WebAuthn **passkey** sign-in to the (single-admin) site, alongside the
existing password login, and an **account settings** page to change the password
and manage passkeys. Passwordless passkey login is offered **automatically** on
the login page via conditional UI (passkey autofill); the password remains a
fully working alternative (and keeps Playwright/CI testing simple). Built
directly on the **Wax** relying-party library — no `webauthn_components`.

## Decisions (locked)

- **Library:** `{:wax_, "~> 0.7"}`, used directly (not the beta `webauthn_components`).
- **Both methods coexist:** passwordless passkey login *and* password login.
- **Usernameless** passkey login (discoverable/resident credentials, empty
  `allowCredentials`).
- **Conditional UI primary:** auto-prompt via `mediation: "conditional"` on the
  login page; a "Sign in with a passkey" button is the fallback for browsers
  without conditional mediation.
- **Settings page** in the admin layout: change password (requires the current
  password) + manage passkeys (name-on-create, list, delete; no rename in v1).
- **Out of scope:** passkey as the *only* factor, recovery codes, multi-user,
  attestation/AAGUID display, passkey rename.

## Configuration

`config :newton, :webauthn, rp_id: "localhost", origin: "http://localhost:4000"`
in dev/test; prod via `runtime.exs` from env (`rp_id: "jamesnewton.com"`,
`origin: "https://jamesnewton.com"`). `rp_id` is the registrable domain; `origin`
is the full scheme+host the browser reports. Wax is configured per-call from
these values.

## Section 1 — Data model

Migration: `user_credentials` table.

`Newton.Accounts.Credential`:

```
field :credential_id, :binary       # raw credential id from the authenticator
field :public_key, :binary          # COSE key, :erlang.term_to_binary/1 of Wax's key
field :sign_count, :integer, default: 0
field :label, :string
field :last_used_at, :utc_datetime
belongs_to :user, Newton.Accounts.User
timestamps()
```

- Unique index on `credential_id`. `User` gets `has_many :credentials`.
- `credential_id`/`public_key`/`sign_count` are server-set (from the verified
  ceremony), never mass-assignable; only `:label` is cast from the form.

## Section 2 — Accounts context additions

- `list_user_credentials(user)` — the user's passkeys, newest first.
- `get_credential_by_external_id(raw_credential_id)` — lookup at login,
  preloading the user.
- `create_credential(user, %{credential_id, public_key, sign_count, label})` —
  store a verified registration.
- `update_credential_sign_count(cred, new_count, used_at)` — after a login.
- `delete_credential(user, id)` — scoped to the owner.
- `update_user_password(user, current_password, attrs)` — wraps the existing
  password change but first verifies `User.valid_password?(user, current_password)`,
  adding a changeset error if wrong. (Self-contained; avoids building sudo-mode
  re-auth UI.)

## Section 3 — Flow A: register a passkey (settings, over the socket)

The user is already authenticated, so no cookie handoff is needed.

1. Settings LiveView, on "Add a passkey", generates a **registration challenge**
   via `Wax.new_registration_challenge(opts)` and keeps it in socket assigns;
   pushes the challenge + options to the client (`push_event`).
2. A `PasskeyRegister` JS hook calls `navigator.credentials.create({publicKey})`
   with `authenticatorSelection: {residentKey: "required", userVerification:
   "preferred"}` (discoverable), base64url-decoding the challenge/ids.
3. The hook sends the attestation back (`pushEvent("passkey_registered", …)`).
4. The LiveView verifies with `Wax.register(attestation_object, client_data_json,
   challenge)`; on success stores the credential (label from the form input,
   `sign_count` from the result) via `create_credential/2` and re-renders the
   list. On failure, a flash error.

## Section 4 — Flow B: sign in with a passkey (login, via controller endpoints)

Login must set the **session cookie**, which a LiveView socket can't do directly,
so the ceremony runs through plain controller endpoints in the public scope:

1. **`GET /login/passkey/challenge`** (`UserSessionController.passkey_challenge`):
   generates `Wax.new_authentication_challenge(allow_credentials: [], …)` (empty
   ⇒ usernameless), stores the challenge bytes in the **session**, returns JSON
   `{challenge, rpId, …}`.
2. **Client:** a `PasskeyAuthenticate` hook on the login page, on mount, checks
   `PublicKeyCredential.isConditionalMediationAvailable()`. If available it fetches
   the challenge and calls `navigator.credentials.get({mediation: "conditional",
   publicKey})` — the browser surfaces passkeys as **autofill** on the email field
   (`autocomplete="username webauthn"`). A fallback **"Sign in with a passkey"**
   button triggers the same with default mediation for unsupported browsers.
3. **`POST /login/passkey`** (`UserSessionController.passkey_login`): receives the
   assertion (credential id, authenticator data, client data, signature, optional
   user handle). Looks up the credential (`get_credential_by_external_id`),
   verifies with `Wax.authenticate(cred_id, auth_data, sig, client_data, challenge,
   %{cred_id => public_key})`, checks the **sign-count** didn't regress, updates
   `sign_count`/`last_used_at`, then `UserAuth.log_in_user(conn, user)` (sets the
   cookie). Responds JSON `{ok: true, to: <signed_in_path>}`; the hook redirects.
   On any failure: 401 JSON `{error}`, the hook shows a message, password form
   still available.

CSRF: the `POST` carries the page's CSRF token (sent by the hook); the GET is
read-only. Challenge is single-use (cleared from the session on use/expiry).

## Section 5 — Flow C: password login (unchanged)

The existing `#login_form_password` + `UserSessionController.create` stay exactly
as they are. The login page simply gains the conditional-UI wiring and the
fallback button.

## Section 6 — Settings page (`/admin/settings`)

A new `NewtonWeb.Admin.SettingsLive`, added to the **existing** admin
`live_session` (`pipe_through [:browser, :require_authenticated_user]`,
`on_mount: :require_authenticated`, `root_layout: admin_root`) — same layout as
the rest of the admin. Two cards:

- **Change password** — current password + new password (+ confirmation) fields;
  `Accounts.update_user_password(user, current, attrs)`. On success, re-establish
  the session (the token-rotation already done by `update_user_and_delete_all_tokens`)
  and flash success.
- **Passkeys** — a list (label · "added <date>" · "last used <date>"), a name
  field + "Add a passkey" (Flow A), and a delete button per row (`delete_credential`).
  A hint that the password still works if no passkeys exist.

A "Settings" link is added to the admin nav.

## Section 7 — JS hooks

- `assets/js/hooks/passkey_register.js` — `PasskeyRegister` (admin bundle):
  decode challenge → `navigator.credentials.create` → encode + `pushEvent`.
- `assets/js/hooks/passkey_authenticate.js` — `PasskeyAuthenticate` (public
  app.js bundle): conditional-UI on mount + fallback button → `fetch` the
  endpoints → `navigator.credentials.get` → redirect.
- Pure, unit-tested helpers in a shared module
  (`assets/js/webauthn.js`): `b64urlToBuf/1`, `bufToB64url/1`, and a
  `credentialToJSON/1` that shapes the assertion/attestation for the server.
- No CSP change: these are `navigator.credentials` calls from bundled scripts
  (`script-src 'self'`) hitting same-origin endpoints (`connect-src 'self'`).

## Security

- Discoverable credentials + user verification preferred. Challenges are random,
  single-use, and bound to the socket (registration) or session (login).
- `rp_id`/`origin` pinned from config; Wax validates the origin and rp id hash.
- Sign-count regression rejected (cloned-authenticator signal).
- `credential_id`/`public_key`/`sign_count` are never mass-assignable; deletes are
  owner-scoped. Deleting the last passkey is allowed (password remains).
- Passwordless login still yields the same session as password login (one code
  path: `UserAuth.log_in_user`).

## Testing approach

- **Accounts context:** create/list/delete credentials (owner-scoped);
  sign-count update; `update_user_password` rejects a wrong current password and
  applies a correct one.
- **Controller:** `passkey_challenge` returns a challenge and stores it in the
  session; `passkey_login` with a **known-good WebAuthn test vector** (or a
  Wax-verified fixture) logs the user in and 401s a bad assertion. (If fixture
  generation is impractical, assert the failure paths deterministically and cover
  the success path in the Playwright e2e below.)
- **Settings LiveView:** wrong current password shows an error; correct one
  changes it; passkey rows render and delete; the control hints when none exist.
- **vitest:** `b64urlToBuf`/`bufToB64url` round-trip; `credentialToJSON` shape.
- **Playwright (PORT=4001) with the CDP virtual authenticator**
  (`WebAuthn.addVirtualAuthenticator`, resident-key + user-verified): full
  round-trip — register a passkey on the settings page, log out, then sign in
  with the passkey (button/modal path; conditional-UI autofill is verified
  manually since the autofill chrome isn't scriptable).

## Unit breakdown

- `priv/repo/migrations/*_create_user_credentials.exs`
- `lib/newton/accounts/credential.ex` (new), `lib/newton/accounts/user.ex` (has_many)
- `lib/newton/accounts.ex` (credential + password fns)
- `lib/newton/webauthn.ex` — thin config/helpers wrapping Wax options
- `lib/newton_web/controllers/user_session_controller.ex` (passkey endpoints)
- `lib/newton_web/router.ex` (two passkey routes; settings live route)
- `lib/newton_web/live/user_live/login.ex` (conditional-UI wiring + fallback button)
- `lib/newton_web/live/admin/settings_live.ex` (new)
- `assets/js/webauthn.js`, `assets/js/hooks/passkey_register.js`,
  `assets/js/hooks/passkey_authenticate.js`; register in `admin.js`/`app.js`
- `mix.exs` (`{:wax_, "~> 0.7"}`), `config/*.exs` (rp_id/origin)

## Build sequencing (for the plan)

1. Settings page + change-password (no WebAuthn) — ships value on its own.
2. Credentials table + Accounts + Wax config + **Flow A** (register, shown on settings).
3. **Flow B** (passwordless login: endpoints + conditional-UI hook).
4. Verification (precommit + Playwright virtual-authenticator e2e).

## Out of scope (future follow-ups)

- Passkey-only accounts / recovery codes; passkey rename; AAGUID/device-type
  display; multi-user; "sudo mode" re-auth for settings.
