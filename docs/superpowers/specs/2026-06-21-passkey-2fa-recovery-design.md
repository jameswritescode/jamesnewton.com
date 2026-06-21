# Require Passkey After Password (2FA) + Recovery Codes — Design Spec

**Date:** 2026-06-21
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Once an account has a passkey enrolled, a password alone must no longer grant
access: a password login becomes the first factor and a **passkey assertion** (or
a **recovery code**) is required as the second. The passwordless passkey path is
unchanged — a passkey alone is still a sufficient strong factor. Recovery codes,
managed in settings, are the lockout escape hatch.

This closes the gap where adding a passkey didn't actually raise the security
floor, because password-only login still worked.

## Decisions (locked)

- Accounts always have email+password (created via `Newton.Release`); passkeys are
  added later in settings. So "has a password" is always true; the new gate keys
  off "has ≥1 passkey".
- **Three valid login outcomes:** passkey alone; password + passkey; password +
  recovery code. **Password alone never suffices when a passkey exists.**
- Passkey-only (conditional UI / button) login is **unchanged**.
- Recovery codes: **10** codes, format `xxxxx-xxxxx`, SHA-256-hashed (the app's
  token-hashing convention), one-time use, shown once on generation.
- The recovery-codes settings section is shown **only when the account has ≥1
  passkey** (the only time lockout is possible).
- Recovery codes are usable **only at the verify step** (i.e., after a correct
  password) — never as a standalone factor.
- **Out of scope:** SMS/TOTP, per-credential 2FA policy, remembering a device to
  skip 2FA, recovery via email.

## Section 1 — Data model & context

- **Migration:** `user_recovery_codes` table — `user_id` (references users,
  `on_delete: :delete_all`, not null), `code_hash :binary` (not null),
  `used_at :utc_datetime` (nullable), timestamps. Unique index on
  `[:user_id, :code_hash]`; index on `user_id`.
- **Schema `Newton.Accounts.RecoveryCode`** — the fields above; no public
  changeset (rows are built server-side).
- **Accounts context:**
  - `has_passkey?(%User{})` → boolean (`Repo.exists?` on credentials).
  - `generate_recovery_codes(%User{})` → replaces the user's codes: deletes all
    existing rows, inserts 10 fresh `{user_id, code_hash}` rows, and **returns the
    10 plaintext codes** (the only time they exist in plaintext). Code = two
    base32 (Crockford, no ambiguous chars) groups of 5, joined by `-`, generated
    from `:crypto.strong_rand_bytes`.
  - `count_unused_recovery_codes(%User{})` → integer.
  - `redeem_recovery_code(%User{}, code)` → normalizes the input (strip spaces,
    upcase), hashes it (`:crypto.hash(:sha256, code)`), and atomically marks the
    matching **unused** row used (`update_all ... where user_id, code_hash,
    is_nil(used_at)`); returns `:ok` if exactly one row was consumed, else
    `:error`.

## Section 2 — Password login gate (`UserSessionController.create`)

After the existing password check succeeds:

```elixir
if user = Accounts.get_user_by_email_and_password(email, password) do
  if Accounts.has_passkey?(user) do
    conn
    |> put_session(:pending_2fa_user_id, user.id)
    |> put_session(:pending_2fa_remember_me, user_params["remember_me"] == "true")
    |> redirect(to: ~p"/login/verify")
  else
    conn |> put_flash(:info, "Welcome back!") |> UserAuth.log_in_user(user, user_params)
  end
else
  # unchanged: generic error, redirect to /login
end
```

`pending_2fa_user_id` confers **no authorization** — only the verify step reads
it, and only to complete the second factor. The remember-me preference is carried
so it still applies after the second factor.

## Section 3 — The verify step (`/login/verify`)

A `NewtonWeb.UserLive.Verify` LiveView in the public `:current_user` live_session
(admin_root layout), plus the existing passkey controller endpoints.

- **Guard:** on mount, if there's no `pending_2fa_user_id` in the session →
  `redirect(to: ~p"/login")`. (The session is available to the LiveView via the
  connect params/session.)
- **Passkey option (primary):** the page auto-runs the passkey assertion (the same
  `PasskeyAuthenticate` flow / endpoints already built) plus a "Use your passkey"
  button. A successful assertion logs in via the existing `passkey_login`
  endpoint (passkey alone is sufficient), which clears any pending state.
- **Recovery-code option:** a "`Use a recovery code`" form (`#recovery-form`) posts
  the code. A new controller action `UserSessionController.recovery_login`:
  - requires `pending_2fa_user_id` (else 401/redirect),
  - `Accounts.redeem_recovery_code(user, code)`,
  - on `:ok` → clear pending session keys, `UserAuth.log_in_user(conn, user, %{"remember_me" => pending_remember_me})`,
  - on `:error` → flash "That code didn't work" and stay on the verify page.
- Route: `post "/login/verify/recovery", UserSessionController, :recovery_login`.

Note: the passkey assertion at this step reuses the existing usernameless
ceremony; it doesn't strictly need `pending_2fa_user_id` because a passkey alone
already authenticates. Recovery codes are the path that *requires* the pending
state, so the password-first guarantee holds for them.

## Section 4 — Settings UI (`SettingsLive`)

Add a **"Recovery codes"** section, rendered only when `Accounts.has_passkey?(@user)`:

- If codes were just generated this session, show the **10 plaintext codes** once,
  in a monospace block, with a Copy button (the existing `CopyText` hook) and a
  note to save them now (they won't be shown again).
- Otherwise show "**N of 10 codes remaining**" (`count_unused_recovery_codes`) and a
  **"Generate recovery codes"** / **"Regenerate"** button. Generating replaces any
  existing set (invalidating old codes) and reveals the new ones once.
- A short line explaining they let you sign in if you lose access to your passkey.

## Error handling / edge cases

- **No pending state at verify:** redirect to `/login` (can't second-factor
  without first factor).
- **Used/invalid recovery code:** `redeem_recovery_code` returns `:error`; flash,
  stay. The atomic `update_all` guard prevents double-spend / races.
- **Account with passkey but zero remaining recovery codes:** still fine — the
  passkey is the primary second factor; recovery codes are the backup. The
  settings UI nudges regeneration when the count is low/zero.
- **Deleting the last passkey:** password-only login returns (the gate keys off
  "has ≥1 passkey"); recovery codes become irrelevant and the section hides.
- **Tests/CI:** test users have no passkeys, so password-only login is unchanged.

## Testing approach

- **Context:** `has_passkey?`; `generate_recovery_codes` returns 10 codes and
  replaces prior ones; `redeem_recovery_code` consumes a valid unused code once
  (second use fails); `count_unused_recovery_codes` reflects redemptions.
- **Controller:** password + an account that has a passkey → redirect to
  `/login/verify` and **no** `user_token` in session; password-only account → logs
  in (unchanged); `recovery_login` with a valid code + pending state → logs in;
  without pending state → rejected; with a bad code → not logged in.
- **Verify LiveView:** no pending → redirect to `/login`; the recovery form
  renders; redeeming a good code navigates to `/admin`.
- **Settings:** the recovery section is hidden without a passkey and shown with
  one; generating reveals 10 codes and updates the remaining count.
- **Playwright (virtual authenticator, PORT=4001):** (a) register a passkey, log
  out, sign in with **password** → land on `/login/verify` → complete the
  **passkey** → `/admin`; (b) generate recovery codes, log out, **password** →
  verify → **recovery code** → `/admin`, and the code is then spent.

## Unit breakdown

- `priv/repo/migrations/*_create_user_recovery_codes.exs`
- `lib/newton/accounts/recovery_code.ex` (schema)
- `lib/newton/accounts.ex` (`has_passkey?/1`, recovery-code fns)
- `lib/newton_web/controllers/user_session_controller.ex` (password gate +
  `recovery_login/2`)
- `lib/newton_web/router.ex` (`/login/verify` live route, recovery POST route)
- `lib/newton_web/live/user_live/verify.ex` (new)
- `lib/newton_web/live/admin/settings_live.ex` (recovery-codes section)

## Out of scope (future follow-ups)

- TOTP/authenticator-app or SMS second factors.
- "Remember this device for 30 days" to skip the second factor.
- Email-based account recovery; admin-initiated reset.
