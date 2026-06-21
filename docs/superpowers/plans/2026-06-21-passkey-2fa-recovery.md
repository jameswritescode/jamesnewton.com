# Passkey-2FA + Recovery Codes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Once an account has a passkey, password login becomes a first factor requiring a passkey assertion (or recovery code) to finish; recovery codes are generated and managed in settings.

**Architecture:** `UserSessionController.create` gates on `Accounts.has_passkey?/1` and, when true, redirects to a `/login/verify` LiveView holding a no-authority `pending_2fa_user_id` in the session. Verify offers the existing passkey ceremony or a recovery-code POST. Recovery codes live in a SHA-256-hashed `user_recovery_codes` table, generated from settings.

**Tech Stack:** Ecto, Phoenix controllers + LiveView, the existing Wax passkey endpoints + `PasskeyAuthenticate` hook, `:crypto` SHA-256, `Phoenix.ConnTest`, Playwright (CDP virtual authenticator, PORT=4001 with `WEBAUTHN_ORIGIN`).

**Reference spec:** `docs/superpowers/specs/2026-06-21-passkey-2fa-recovery-design.md`

**Session constraints:** Commit signed (1Password; if it fails, `--no-gpg-sign` then re-sign). Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Servers on `PORT=4001`, never 4000; passkey e2e needs `WEBAUTHN_ORIGIN=http://localhost:4001`. Browser checks use Playwright. Do not modify `config/dev.exs`.

---

## Task 1: Recovery codes data model + context (and `has_passkey?`)

**Files:**
- Create: `priv/repo/migrations/*_create_user_recovery_codes.exs`, `lib/newton/accounts/recovery_code.ex`
- Modify: `lib/newton/accounts.ex` (alias + functions)
- Test: `test/newton/accounts_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/accounts_test.exs`:

```elixir
  describe "passkey presence + recovery codes" do
    test "has_passkey? reflects stored credentials" do
      user = user_fixture()
      refute Accounts.has_passkey?(user)

      {:ok, _} =
        Accounts.create_credential(user, %{
          credential_id: <<7, 7>>,
          public_key: :erlang.term_to_binary(%{1 => 2}),
          sign_count: 0,
          label: "K"
        })

      assert Accounts.has_passkey?(user)
    end

    test "generate_recovery_codes returns 10 codes, replaces old ones, and counts" do
      user = user_fixture()
      codes = Accounts.generate_recovery_codes(user)
      assert length(codes) == 10
      assert Enum.all?(codes, &(&1 =~ ~r/^[A-Z0-9]{5}-[A-Z0-9]{5}$/))
      assert Accounts.count_unused_recovery_codes(user) == 10

      new_codes = Accounts.generate_recovery_codes(user)
      assert Accounts.count_unused_recovery_codes(user) == 10
      # old codes no longer redeemable
      assert Accounts.redeem_recovery_code(user, hd(codes)) == :error
      assert Accounts.redeem_recovery_code(user, hd(new_codes)) == :ok
    end

    test "redeem_recovery_code consumes a code exactly once and is input-lenient" do
      user = user_fixture()
      [code | _] = Accounts.generate_recovery_codes(user)

      # lower-case + spaces still match
      messy = String.downcase(String.replace(code, "-", " "))
      assert Accounts.redeem_recovery_code(user, messy) == :ok
      assert Accounts.redeem_recovery_code(user, code) == :error
      assert Accounts.count_unused_recovery_codes(user) == 9
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton/accounts_test.exs` — FAIL (undefined functions).

- [ ] **Step 3: Migration**

`mix ecto.gen.migration create_user_recovery_codes`, body:

```elixir
def change do
  create table(:user_recovery_codes) do
    add :user_id, references(:users, on_delete: :delete_all), null: false
    add :code_hash, :binary, null: false
    add :used_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  create unique_index(:user_recovery_codes, [:user_id, :code_hash])
  create index(:user_recovery_codes, [:user_id])
end
```

Run `mix ecto.migrate`.

- [ ] **Step 4: Schema**

Create `lib/newton/accounts/recovery_code.ex`:

```elixir
defmodule Newton.Accounts.RecoveryCode do
  use Ecto.Schema

  schema "user_recovery_codes" do
    field :code_hash, :binary
    field :used_at, :utc_datetime
    belongs_to :user, Newton.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
```

- [ ] **Step 5: Context functions**

In `lib/newton/accounts.ex`, extend the alias to include `RecoveryCode`:

```elixir
  alias Newton.Accounts.{Credential, RecoveryCode, User, UserNotifier, UserToken}
```

Add the functions:

```elixir
  @doc "True if the user has at least one passkey credential."
  def has_passkey?(%User{id: id}), do: Repo.exists?(from c in Credential, where: c.user_id == ^id)

  # Unambiguous alphabet (no 0/O/1/I/L/U); 10 chars shown as `xxxxx-xxxxx`.
  @recovery_alphabet ~c"23456789ABCDEFGHJKMNPQRSTVWXYZ"
  @recovery_count 10

  @doc "Replace the user's recovery codes with 10 fresh ones; returns the plaintext codes."
  def generate_recovery_codes(%User{id: user_id} = user) do
    Repo.delete_all(from r in RecoveryCode, where: r.user_id == ^user_id)
    codes = for _ <- 1..@recovery_count, do: random_recovery_code()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(codes, fn code ->
        %{user_id: user_id, code_hash: hash_recovery_code(code), inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(RecoveryCode, rows)
    _ = user
    codes
  end

  @doc "How many of the user's recovery codes are still unused."
  def count_unused_recovery_codes(%User{id: user_id}) do
    Repo.aggregate(from(r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at)), :count)
  end

  @doc "Consume a matching unused recovery code; `:ok` if exactly one was spent, else `:error`."
  def redeem_recovery_code(%User{id: user_id}, code) when is_binary(code) do
    hash = hash_recovery_code(code)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.update_all(
        from(r in RecoveryCode,
          where: r.user_id == ^user_id and r.code_hash == ^hash and is_nil(r.used_at)
        ),
        set: [used_at: now, updated_at: now]
      )

    if count == 1, do: :ok, else: :error
  end

  defp random_recovery_code do
    chars =
      :crypto.strong_rand_bytes(10)
      |> :binary.bin_to_list()
      |> Enum.map(&Enum.at(@recovery_alphabet, rem(&1, length(@recovery_alphabet))))
      |> List.to_string()

    String.slice(chars, 0, 5) <> "-" <> String.slice(chars, 5, 5)
  end

  # Normalize (upcase, strip non-alphanumerics) before hashing so lenient input matches.
  defp hash_recovery_code(code) do
    normalized = code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")
    :crypto.hash(:sha256, normalized)
  end
```

Run: `mix test test/newton/accounts_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations lib/newton/accounts/recovery_code.ex lib/newton/accounts.ex test/newton/accounts_test.exs
git commit -m "$(cat <<'EOF'
Add recovery codes and has_passkey? to the Accounts context

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Password login gate + recovery_login endpoint

**Files:**
- Modify: `lib/newton_web/controllers/user_session_controller.ex`, `lib/newton_web/router.ex`
- Test: `test/newton_web/controllers/user_session_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/controllers/user_session_controller_test.exs` (the `setup` already gives `%{user: user_fixture()}`; `set_password/1` and `valid_user_password/0` come from `Newton.AccountsFixtures`):

```elixir
  describe "password login with a passkey present (2FA gate)" do
    setup %{user: user} do
      user = set_password(user)

      {:ok, _} =
        Newton.Accounts.create_credential(user, %{
          credential_id: <<5, 5, 5>>,
          public_key: :erlang.term_to_binary(%{1 => 2}),
          sign_count: 0,
          label: "K"
        })

      %{user: user}
    end

    test "redirects to verify and does not log in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/login/verify"
      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_2fa_user_id) == user.id
    end

    test "recovery_login with a valid code completes the login", %{conn: conn, user: user} do
      [code | _] = Newton.Accounts.generate_recovery_codes(user)

      conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})
      conn = post(conn, ~p"/login/verify/recovery", %{"code" => code})

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)
    end

    test "recovery_login without a pending session is rejected", %{conn: conn} do
      conn = post(conn, ~p"/login/verify/recovery", %{"code" => "WHATEVER"})
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
    end

    test "recovery_login with a bad code stays on verify", %{conn: conn, user: user} do
      _ = Newton.Accounts.generate_recovery_codes(user)
      conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})
      conn = post(conn, ~p"/login/verify/recovery", %{"code" => "00000-00000"})

      assert redirected_to(conn) == ~p"/login/verify"
      refute get_session(conn, :user_token)
    end
  end

  test "password login with no passkey still logs in directly", %{conn: conn, user: user} do
    user = set_password(user)
    conn = post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => valid_user_password()}})
    assert get_session(conn, :user_token)
    assert redirected_to(conn) == ~p"/admin"
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/controllers/user_session_controller_test.exs` — FAIL (no gate/route yet; the redirect goes to `/admin`).

- [ ] **Step 3: Routes**

In `lib/newton_web/router.ex`, in the public auth scope (next to the other `/login` routes), add:

```elixir
    post "/login/verify/recovery", UserSessionController, :recovery_login
```

(The `/login/verify` LiveView route is added in Task 3.)

- [ ] **Step 4: Gate `create/2` and add `recovery_login/2`**

In `lib/newton_web/controllers/user_session_controller.ex`, change `create/2`'s success branch and add the recovery action:

```elixir
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

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
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def recovery_login(conn, %{"code" => code}) do
    case get_session(conn, :pending_2fa_user_id) do
      nil ->
        redirect(conn, to: ~p"/login")

      user_id ->
        user = Accounts.get_user!(user_id)

        case Accounts.redeem_recovery_code(user, code) do
          :ok ->
            remember = get_session(conn, :pending_2fa_remember_me)

            conn
            |> put_flash(:info, "Welcome back!")
            |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember)})

          :error ->
            conn
            |> put_flash(:error, "That code didn't work. Try another.")
            |> redirect(to: ~p"/login/verify")
        end
    end
  end
```

(`UserAuth.log_in_user` renews the session, which drops the `pending_2fa_*` keys.)

- [ ] **Step 5: Run them to verify they pass**

Run: `mix test test/newton_web/controllers/user_session_controller_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/controllers/user_session_controller.ex lib/newton_web/router.ex test/newton_web/controllers/user_session_controller_test.exs
git commit -m "$(cat <<'EOF'
Require a second factor when a password account has a passkey

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The `/login/verify` step

**Files:**
- Create: `lib/newton_web/live/user_live/verify.ex`
- Modify: `lib/newton_web/router.ex`
- Test: `test/newton_web/live/user_live/verify_live_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/newton_web/live/user_live/verify_live_test.exs`:

```elixir
defmodule NewtonWeb.UserLive.VerifyTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  test "redirects to /login when there is no pending second factor", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/login/verify")
  end

  test "renders the verify page and the recovery form when pending", %{conn: conn} do
    user = set_password(user_fixture())

    conn = Plug.Test.init_test_session(conn, %{"pending_2fa_user_id" => user.id})
    {:ok, _view, html} = live(conn, ~p"/login/verify")
    assert html =~ "passkey"
    assert html =~ "recovery code"
    assert html =~ ~s(action="/login/verify/recovery")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/user_live/verify_live_test.exs` — FAIL (no route/LiveView).

- [ ] **Step 3: Add the route**

In `lib/newton_web/router.ex`, inside the existing `live_session :current_user` block (next to `live "/login", UserLive.Login, :new`):

```elixir
      live "/login/verify", UserLive.Verify, :new
```

- [ ] **Step 4: Implement the LiveView**

Create `lib/newton_web/live/user_live/verify.ex`. It reuses the public `PasskeyAuthenticate` hook (already in `app.js`/`admin.js`; this page uses the `admin_root` layout → admin bundle) and posts the recovery form to the controller.

```elixir
defmodule NewtonWeb.UserLive.Verify do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts, as: AdminLayouts

  @impl true
  def mount(_params, session, socket) do
    if session["pending_2fa_user_id"] do
      {:ok, assign(socket, show_recovery: false), layout: false}
    else
      {:ok, push_navigate(socket, to: ~p"/login"), layout: false}
    end
  end

  @impl true
  def handle_event("show_recovery", _params, socket) do
    {:noreply, assign(socket, :show_recovery, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center px-4">
      <div class="w-full max-w-sm">
        <div class="mb-6 flex items-center justify-center gap-2 text-[1.05rem] font-semibold tracking-tight text-(--admin-text)">
          <span class="size-2.5 rounded-full bg-(--admin-accent)"></span> newton
        </div>

        <div class="rounded-xl border border-(--admin-border) bg-(--admin-surface) p-6 shadow-sm">
          <h1 class="text-[1.1rem] font-semibold text-(--admin-text)">Confirm it's you</h1>
          <p class="mt-1 mb-5 text-[0.82rem] text-(--admin-text-subtle)">
            Use your passkey to finish signing in.
          </p>

          <div id="passkey-login" phx-hook="PasskeyAuthenticate">
            <button
              type="button"
              id="passkey-button"
              class="w-full rounded-md bg-(--admin-accent) px-3 py-2 text-[0.85rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Use your passkey
            </button>
          </div>

          <button
            :if={!@show_recovery}
            type="button"
            phx-click="show_recovery"
            class="mt-4 w-full text-center text-[0.78rem] text-(--admin-text-muted) hover:text-(--admin-text)"
          >
            Use a recovery code instead
          </button>

          <form
            :if={@show_recovery}
            action={~p"/login/verify/recovery"}
            method="post"
            class="mt-4 flex flex-col gap-2"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <label class="text-[0.78rem] text-(--admin-text-muted)">Recovery code</label>
            <input
              type="text"
              name="code"
              autocomplete="one-time-code"
              spellcheck="false"
              required
              class="w-full rounded-md border border-(--admin-border) bg-(--admin-bg) px-3 py-2 text-[0.85rem] text-(--admin-text) focus:border-(--admin-accent) focus:outline-none"
            />
            <button
              type="submit"
              class="rounded-md border border-(--admin-border) px-3 py-2 text-[0.85rem] font-medium text-(--admin-text) hover:bg-(--admin-accent-soft)"
            >
              Sign in with recovery code
            </button>
          </form>
        </div>

        <AdminLayouts.admin_flash_group flash={@flash} />
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/newton_web/live/user_live/verify_live_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/user_live/verify.ex lib/newton_web/router.ex test/newton_web/live/user_live/verify_live_test.exs
git commit -m "$(cat <<'EOF'
Add the second-factor verify step

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Recovery codes section in settings

**Files:**
- Modify: `lib/newton_web/live/admin/settings_live.ex`
- Test: `test/newton_web/live/admin/settings_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/live/admin/settings_live_test.exs`:

```elixir
  test "recovery codes section is hidden without a passkey and shown with one", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/admin/settings")
    refute html =~ "Recovery codes"

    {:ok, _} =
      Newton.Accounts.create_credential(user, %{
        credential_id: <<3, 3, 3>>,
        public_key: :erlang.term_to_binary(%{1 => 2}),
        sign_count: 0,
        label: "K"
      })

    {:ok, view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "Recovery codes"

    html = view |> element("button", "Generate recovery codes") |> render_click()
    # 10 codes revealed once
    assert length(Regex.scan(~r/[A-Z0-9]{5}-[A-Z0-9]{5}/, html)) == 10
    assert Newton.Accounts.count_unused_recovery_codes(user) == 10
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs` — FAIL (no recovery UI/event).

- [ ] **Step 3: Mount assigns + event**

In `lib/newton_web/live/admin/settings_live.ex` `mount/3`, add assigns:

```elixir
     |> assign(:recovery_count, Accounts.count_unused_recovery_codes(user))
     |> assign(:new_recovery_codes, nil)
```

Add the event:

```elixir
  def handle_event("generate_recovery_codes", _params, socket) do
    codes = Accounts.generate_recovery_codes(socket.assigns.user)

    {:noreply,
     socket
     |> assign(:new_recovery_codes, codes)
     |> assign(:recovery_count, length(codes))
     |> put_flash(:info, "Recovery codes generated. Save them now — they won't be shown again.")}
  end
```

- [ ] **Step 4: Render the section**

In the template, after the Passkeys `</section>`, add (only when a passkey exists):

```heex
      <section :if={@credentials != []} class="mt-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Recovery codes</h2>
        <p class="mb-3 text-[0.82rem] text-(--admin-text-subtle)">
          Use a recovery code to sign in if you lose access to your passkey.
        </p>

        <div :if={@new_recovery_codes} class="mb-3">
          <pre
            id="recovery-codes"
            phx-no-curly-interpolation
            class="grid grid-cols-2 gap-x-6 gap-y-1 rounded-md border border-(--admin-border) bg-(--admin-bg) p-3 font-mono text-[0.85rem] text-(--admin-text)"
          ><span :for={code <- @new_recovery_codes}>{code}</span></pre>
          <p class="mt-1 text-[0.72rem] text-(--admin-text-subtle)">
            Save these now — they won't be shown again.
          </p>
        </div>

        <p :if={!@new_recovery_codes} class="mb-3 text-[0.82rem] text-(--admin-text-muted)">
          {@recovery_count} of 10 codes remaining.
        </p>

        <Components.button phx-click="generate_recovery_codes">
          {if @recovery_count > 0 and is_nil(@new_recovery_codes),
            do: "Regenerate recovery codes",
            else: "Generate recovery codes"}
        </Components.button>
      </section>
```

- [ ] **Step 5: Run it to verify it passes**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/admin/settings_live.ex test/newton_web/live/admin/settings_live_test.exs
git commit -m "$(cat <<'EOF'
Add recovery codes management to settings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Full verification + Playwright e2e

- [ ] **Step 1: precommit**

Run: `mix precommit` — PASS (format, compile, credo, dialyzer, full `mix test`, JS suite). Fix findings (don't disable linters).

- [ ] **Step 2: Playwright e2e (virtual authenticator)**

Build assets; start `WEBAUTHN_ORIGIN=http://localhost:4001 PORT=4001 mix phx.server`. Add a CDP virtual authenticator (resident key, user-verified) and a `assets/twofa_e2e.mjs` that:
1. logs in with the password, opens `/admin/settings`, registers a passkey, then clicks **Generate recovery codes** and captures the 10 codes from `#recovery-codes`;
2. logs out; signs in with **password** → asserts the URL is `/login/verify` (not `/admin`); completes the **passkey** (button) → asserts `/admin`;
3. logs out; signs in with **password** → `/login/verify` → clicks "Use a recovery code instead", submits one captured code → asserts `/admin`; then asserts that same code now fails (redeem returns error → stays on verify on a second attempt).

Run: `cd assets && node twofa_e2e.mjs`. Expected: all assertions pass.

- [ ] **Step 3: Clean up**

Remove `assets/twofa_e2e.mjs`; delete any test credentials/recovery codes seeded in the dev DB (`E2E`/that user); stop the PORT=4001 server; confirm `config/dev.exs` untouched.

- [ ] **Step 4: Commit any verification fixes** (only if needed)

```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix issues found verifying passkey 2FA + recovery codes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** `has_passkey?` + recovery-code schema/context (Task 1); password gate + recovery_login + pending session (Task 2); verify step with passkey + recovery form (Task 3); settings recovery section, passkey-gated, generate/show-once/count (Task 4); e2e for both finishes (Task 5). Out-of-scope items (TOTP, remember-device, email recovery) omitted.
- **Type/name consistency:** `has_passkey?/1`, `generate_recovery_codes/1`, `count_unused_recovery_codes/1`, `redeem_recovery_code/2` defined in Task 1 and used identically in Tasks 2 & 4; session keys `pending_2fa_user_id` / `pending_2fa_remember_me` written in Task 2 and read in Tasks 2 (recovery_login) & 3 (verify mount); the recovery POST path `/login/verify/recovery` matches across the route (Task 2), the form `action` (Task 3), and the controller test (Task 2); `Components.button` (admin) and `PasskeyAuthenticate` hook reused as already built.
- **Security:** `pending_2fa_*` confers no authorization; only `redeem_recovery_code` (atomic `update_all` guard, single-use) and the passkey ceremony establish a session; any login renews/clears the session, dropping pending keys. Recovery codes require the password step (the pending session), so they're never a standalone factor.
