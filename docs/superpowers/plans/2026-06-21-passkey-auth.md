# Passkey Authentication + Account Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WebAuthn passkey sign-in (passwordless, conditional-UI autofill) alongside the existing password login, plus an `/admin/settings` page to change the password and manage passkeys — built directly on the Wax library.

**Architecture:** A `user_credentials` table holds each passkey. Registration runs over the settings LiveView socket (already authenticated — no cookie to set); passwordless login runs through controller endpoints (which *can* set the session cookie) and is triggered automatically via conditional UI on the login page. Wax verifies both ceremonies. The password path is untouched and remains the testing/fallback method.

**Tech Stack:** `wax_` (FIDO2 RP), Ecto, Phoenix controllers + LiveView, JS hooks calling `navigator.credentials`, vitest, `Phoenix.ConnTest`, Playwright with the CDP virtual authenticator.

**Reference spec:** `docs/superpowers/specs/2026-06-21-passkey-auth-design.md`

**Session constraints:** Commit signed (1Password; if it fails, commit `--no-gpg-sign` and re-sign later). Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Servers run on `PORT=4001`, never 4000. Browser verification uses Playwright. Previewing real error pages in dev needs `debug_errors: false` temporarily (not needed here unless testing 401 pages).

---

## Task 1: Account settings page + change password (no WebAuthn)

Ships standalone value and has zero WebAuthn risk.

**Files:**
- Modify: `lib/newton/accounts.ex` (current-password-checked update)
- Modify: `lib/newton_web/router.ex` (settings route in the admin live_session)
- Modify: `lib/newton_web/components/admin/layouts.ex` (nav entry)
- Create: `lib/newton_web/live/admin/settings_live.ex`
- Test: `test/newton/accounts_test.exs`, `test/newton_web/live/admin/settings_live_test.exs`

- [ ] **Step 1: Write the failing context test**

In `test/newton/accounts_test.exs` add (uses the existing `user_fixture/1`):

```elixir
  describe "update_user_password/3 (current-password checked)" do
    test "rejects a wrong current password" do
      user = user_fixture()
      assert {:error, changeset} =
               Accounts.update_user_password(user, "wrong", %{password: "new valid password"})
      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "changes the password with the correct current password" do
      user = user_fixture()
      assert {:ok, {updated, _expired}} =
               Accounts.update_user_password(user, valid_user_password(), %{
                 password: "another valid password"
               })
      assert Accounts.get_user_by_email_and_password(updated.email, "another valid password")
    end
  end
```

(If `valid_user_password/0`/`user_fixture/1` aren't imported, add `import Newton.AccountsFixtures`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/accounts_test.exs` — FAIL (arity/clause missing).

- [ ] **Step 3: Add the current-password-checked update**

In `lib/newton/accounts.ex`, add a new clause (keep the existing `update_user_password/2` for internal callers):

```elixir
  @doc "Change the password after verifying the supplied current password."
  def update_user_password(user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> maybe_validate_current_password(user, current_password)

    if changeset.valid? do
      update_user_and_delete_all_tokens(changeset)
    else
      {:error, %{changeset | action: :update}}
    end
  end

  defp maybe_validate_current_password(changeset, user, current_password) do
    if User.valid_password?(user, current_password) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :current_password, "is not valid")
    end
  end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/newton/accounts_test.exs` — PASS.

- [ ] **Step 5: Add the settings route + nav entry**

In `lib/newton_web/router.ex`, inside the `live_session :admin` block, add:

```elixir
      live "/settings", SettingsLive, :edit
```

In `lib/newton_web/components/admin/layouts.ex`, add to `@sections` (after photos) and to `@built`:

```elixir
    %{key: :photos, label: "Photos", path: "/admin/photos"},
    %{key: :settings, label: "Settings", path: "/admin/settings"}
  ]

  @built [:dashboard, :posts, :reading, :photos, :settings]
```

- [ ] **Step 6: Write the failing LiveView test**

Create `test/newton_web/live/admin/settings_live_test.exs`:

```elixir
defmodule NewtonWeb.Admin.SettingsLiveTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "renders the settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "Change password"
    assert html =~ "Passkeys"
  end

  test "a wrong current password shows an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")

    html =
      view
      |> form("#password-form", %{
        current_password: "nope",
        user: %{password: "a brand new password", password_confirmation: "a brand new password"}
      })
      |> render_submit()

    assert html =~ "is not valid"
  end

  test "the correct current password changes it", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")

    view
    |> form("#password-form", %{
      current_password: valid_user_password(),
      user: %{password: "a brand new password", password_confirmation: "a brand new password"}
    })
    |> render_submit()

    assert Newton.Accounts.get_user_by_email_and_password(user.email, "a brand new password")
  end
end
```

- [ ] **Step 7: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs` — FAIL (no SettingsLive).

- [ ] **Step 8: Implement SettingsLive (password section; passkeys placeholder)**

Create `lib/newton_web/live/admin/settings_live.ex`. The passkey list/add UI is filled in by Task 3; for now render a "Passkeys" heading and an empty-state so the page is complete.

```elixir
defmodule NewtonWeb.Admin.SettingsLive do
  use NewtonWeb, :live_view

  alias Newton.Accounts
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:user, user)
     |> assign(:password_form, password_form())}
  end

  defp password_form, do: to_form(Accounts.change_user_password(%Accounts.User{}), as: :user)

  @impl true
  def handle_event("save_password", params, socket) do
    %{"current_password" => current, "user" => user_params} = params

    case Accounts.update_user_password(socket.assigns.user, current, user_params) do
      {:ok, {user, _}} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:password_form, password_form())
         |> put_flash(:info, "Password updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :user))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:settings}>
      <h1 class="mb-6 text-[1.35rem] font-semibold tracking-tight">Settings</h1>

      <section class="mb-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Change password</h2>
        <.form for={@password_form} id="password-form" phx-submit="save_password" class="flex flex-col gap-3">
          <.input
            name="current_password"
            type="password"
            label="Current password"
            value=""
            autocomplete="current-password"
          />
          <.input field={@password_form[:password]} type="password" label="New password" autocomplete="new-password" />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <button type="submit" class="self-start rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white">
            Update password
          </button>
        </.form>
      </section>

      <section class="max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Passkeys</h2>
        <p class="text-[0.82rem] text-(--admin-text-subtle)">
          No passkeys yet. Your password still works as a sign-in method.
        </p>
      </section>
    </Layouts.admin>
    """
  end
end
```

Note: `password_confirmation` — `User.password_changeset` calls `validate_confirmation(:password)`, so the field name is `password_confirmation`.

- [ ] **Step 9: Run the settings tests**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs` — PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/newton/accounts.ex lib/newton_web/router.ex lib/newton_web/components/admin/layouts.ex lib/newton_web/live/admin/settings_live.ex test/newton/accounts_test.exs test/newton_web/live/admin/settings_live_test.exs
git commit -m "$(cat <<'EOF'
Add an admin settings page with change-password

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wax dependency, config, credentials store, and a shape spike

**Files:**
- Modify: `mix.exs`, `config/config.exs`, `config/test.exs`, `config/runtime.exs`
- Create: `priv/repo/migrations/*_create_user_credentials.exs`, `lib/newton/accounts/credential.ex`, `lib/newton/webauthn.ex`
- Modify: `lib/newton/accounts/user.ex` (has_many), `lib/newton/accounts.ex` (credential fns)
- Test: `test/newton/accounts_test.exs`

- [ ] **Step 1: Add the dependency and config**

In `mix.exs` deps: `{:wax_, "~> 0.7"}`. Run `mix deps.get`.

`config/config.exs`:
```elixir
config :newton, :webauthn, rp_id: "localhost", origin: "http://localhost:4000"
```
`config/test.exs`: same (`rp_id: "localhost", origin: "http://localhost:4000"`).
`config/runtime.exs` (inside the `PHX_SERVER`/prod block):
```elixir
config :newton, :webauthn,
  rp_id: System.get_env("PHX_HOST") || "jamesnewton.com",
  origin: "https://" <> (System.get_env("PHX_HOST") || "jamesnewton.com")
```

- [ ] **Step 2: Generate + write the migration**

Run `mix ecto.gen.migration create_user_credentials`, then:

```elixir
def change do
  create table(:user_credentials) do
    add :user_id, references(:users, on_delete: :delete_all), null: false
    add :credential_id, :binary, null: false
    add :public_key, :binary, null: false
    add :sign_count, :integer, null: false, default: 0
    add :label, :string
    add :last_used_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  create unique_index(:user_credentials, [:credential_id])
  create index(:user_credentials, [:user_id])
end
```

Run `mix ecto.migrate`.

- [ ] **Step 3: Credential schema + user association**

Create `lib/newton/accounts/credential.ex`:

```elixir
defmodule Newton.Accounts.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :label, :string
    field :last_used_at, :utc_datetime
    belongs_to :user, Newton.Accounts.User
    timestamps(type: :utc_datetime)
  end

  @doc "Only the human label is form-assignable; key material is set by the server."
  def label_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:label])
    |> validate_required([:label])
    |> validate_length(:label, max: 60)
  end
end
```

In `lib/newton/accounts/user.ex`, add to the schema: `has_many :credentials, Newton.Accounts.Credential`.

- [ ] **Step 4: Context functions (with tests)**

Add tests to `test/newton/accounts_test.exs`:

```elixir
  describe "credentials" do
    test "create, list, and delete are owner-scoped" do
      user = user_fixture()
      other = user_fixture()

      {:ok, cred} =
        Accounts.create_credential(user, %{
          credential_id: <<1, 2, 3>>,
          public_key: :erlang.term_to_binary(%{1 => 2}),
          sign_count: 0,
          label: "Laptop"
        })

      assert [%{label: "Laptop"}] = Accounts.list_user_credentials(user)
      assert Accounts.list_user_credentials(other) == []

      assert Accounts.get_credential_by_external_id(<<1, 2, 3>>).user_id == user.id
      assert Accounts.delete_credential(other, cred.id) == :error
      assert {:ok, _} = Accounts.delete_credential(user, cred.id)
      assert Accounts.list_user_credentials(user) == []
    end
  end
```

Then implement in `lib/newton/accounts.ex` (add `alias Newton.Accounts.Credential`):

```elixir
  def list_user_credentials(%User{id: id}) do
    Repo.all(from c in Credential, where: c.user_id == ^id, order_by: [desc: c.inserted_at])
  end

  def get_credential_by_external_id(credential_id) do
    Repo.one(from c in Credential, where: c.credential_id == ^credential_id, preload: :user)
  end

  def create_credential(%User{id: user_id}, attrs) do
    %Credential{user_id: user_id}
    |> Credential.label_changeset(Map.take(attrs, [:label]))
    |> Ecto.Changeset.put_change(:credential_id, attrs.credential_id)
    |> Ecto.Changeset.put_change(:public_key, attrs.public_key)
    |> Ecto.Changeset.put_change(:sign_count, attrs.sign_count)
    |> Repo.insert()
  end

  def update_credential_sign_count(%Credential{} = cred, count, used_at) do
    cred
    |> Ecto.Changeset.change(sign_count: count, last_used_at: used_at)
    |> Repo.update()
  end

  def delete_credential(%User{id: user_id}, id) do
    case Repo.get_by(Credential, id: id, user_id: user_id) do
      nil -> :error
      cred -> Repo.delete(cred)
    end
  end
```

Run: `mix test test/newton/accounts_test.exs` — PASS.

- [ ] **Step 5: Wax wrapper module**

Create `lib/newton/webauthn.ex` — centralizes rp_id/origin and the cose-key (de)serialization:

```elixir
defmodule Newton.Webauthn do
  @moduledoc "Thin wrapper over Wax: applies our configured rp_id/origin."

  def opts(extra \\ []) do
    cfg = Application.fetch_env!(:newton, :webauthn)
    Keyword.merge([rp_id: cfg[:rp_id], origin: cfg[:origin]], extra)
  end

  def registration_challenge, do: Wax.new_registration_challenge(opts())

  def authentication_challenge,
    do: Wax.new_authentication_challenge(opts(allow_credentials: []))

  def dump_key(cose_key), do: :erlang.term_to_binary(cose_key)
  def load_key(bin), do: :erlang.binary_to_term(bin)
end
```

- [ ] **Step 6: Spike — confirm Wax result shapes in iex**

Before writing the ceremonies, confirm the exact fields. Run `iex -S mix` and:

```elixir
c = Newton.Webauthn.registration_challenge()
# Inspect: c.bytes (challenge), c.rp_id, c.user_verification
# After a real register/3 returns {:ok, {auth_data, _attestation}}, confirm:
#   auth_data.attested_credential_data.credential_id
#   auth_data.attested_credential_data.credential_public_key   (the COSE key to store)
#   auth_data.sign_count
```

Record the exact field paths in a comment at the top of `lib/newton/webauthn.ex` so Tasks 3–4 use the real names. (Wax ≥0.6 uses `attested_credential_data`; verify against the installed version's `Wax.AuthenticatorData`/`Wax.AttestedCredentialData` docs.)

- [ ] **Step 7: Commit**

```bash
git add mix.exs mix.lock config priv/repo/migrations lib/newton/accounts/credential.ex lib/newton/accounts/user.ex lib/newton/accounts.ex lib/newton/webauthn.ex test/newton/accounts_test.exs
git commit -m "$(cat <<'EOF'
Add Wax, a credentials store, and webauthn config

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Register a passkey (settings page, over the socket)

**Files:**
- Create: `assets/js/webauthn.js`, `assets/js/hooks/passkey_register.js`, `assets/js/webauthn.test.js`
- Modify: `assets/js/admin.js` (register hook), `lib/newton_web/live/admin/settings_live.ex` (passkey UI + events)
- Modify: `test/newton_web/live/admin/settings_live_test.exs`

- [ ] **Step 1: Write + pass the JS helper unit tests**

Create `assets/js/webauthn.test.js` testing pure helpers, then implement `assets/js/webauthn.js`:

```js
// assets/js/webauthn.js
export function bufToB64url(buf) {
  const bytes = new Uint8Array(buf)
  let bin = ""
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export function b64urlToBuf(s) {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4))
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes.buffer
}
```

Test: `b64urlToBuf(bufToB64url(x))` round-trips; known vectors decode correctly. Run `cd assets && pnpm vitest run js/webauthn.test.js` (fails first, then passes).

- [ ] **Step 2: The PasskeyRegister hook**

Create `assets/js/hooks/passkey_register.js`:

```js
import {bufToB64url, b64urlToBuf} from "../webauthn"

// Server pushes "passkey_create" with the PublicKeyCredentialCreationOptions
// (challenge/user.id/excludeCredentials base64url-encoded). We run
// navigator.credentials.create and send the attestation back.
export const PasskeyRegister = {
  mounted() {
    this.handleEvent("passkey_create", async (opts) => {
      try {
        const publicKey = {
          ...opts,
          challenge: b64urlToBuf(opts.challenge),
          user: {...opts.user, id: b64urlToBuf(opts.user.id)},
          excludeCredentials: (opts.excludeCredentials || []).map((c) => ({
            ...c,
            id: b64urlToBuf(c.id),
          })),
        }
        const cred = await navigator.credentials.create({publicKey})
        this.pushEvent("passkey_registered", {
          rawId: bufToB64url(cred.rawId),
          clientDataJSON: bufToB64url(cred.response.clientDataJSON),
          attestationObject: bufToB64url(cred.response.attestationObject),
          label: this.el.dataset.label || "",
        })
      } catch (e) {
        this.pushEvent("passkey_error", {message: String(e)})
      }
    })
  },
}
```

Register it in `assets/js/admin.js` (import + add `PasskeyRegister` to the hooks map).

- [ ] **Step 3: Settings LiveView — passkey list + register events**

Extend `lib/newton_web/live/admin/settings_live.ex`:
- `mount` also assigns `:credentials` (`Accounts.list_user_credentials(user)`) and `:reg_challenge` nil.
- Add the passkey section UI: an element with `id="passkey-register" phx-hook="PasskeyRegister" data-label={@new_label}`, a label input, an "Add a passkey" button (`phx-click="start_registration"`), the credential list (label · added · last used) each with a delete button (`phx-click="delete_passkey" phx-value-id={c.id}`).
- Events:

```elixir
  def handle_event("start_registration", _params, socket) do
    challenge = Newton.Webauthn.registration_challenge()
    user = socket.assigns.user

    creation_opts = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{id: challenge.rp_id, name: "James Newton"},
      user: %{
        id: Base.url_encode64(<<user.id::64>>, padding: false),
        name: user.email,
        displayName: user.email
      },
      pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
      authenticatorSelection: %{residentKey: "required", userVerification: "preferred"},
      excludeCredentials:
        Enum.map(socket.assigns.credentials, fn c ->
          %{type: "public-key", id: Base.url_encode64(c.credential_id, padding: false)}
        end)
    }

    {:noreply,
     socket
     |> assign(:reg_challenge, challenge)
     |> push_event("passkey_create", creation_opts)}
  end

  def handle_event("passkey_registered", params, socket) do
    %{"rawId" => raw_id, "clientDataJSON" => cdj, "attestationObject" => att, "label" => label} = params
    challenge = socket.assigns.reg_challenge

    with {:ok, att_obj} <- Base.url_decode64(att, padding: false),
         {:ok, client_data} <- Base.url_decode64(cdj, padding: false),
         {:ok, {auth_data, _}} <- Wax.register(att_obj, client_data, challenge),
         {:ok, cred_id} <- Base.url_decode64(raw_id, padding: false) do
      # NOTE: field paths confirmed by the Task 2 spike.
      {:ok, _} =
        Accounts.create_credential(socket.assigns.user, %{
          credential_id: cred_id,
          public_key: Newton.Webauthn.dump_key(auth_data.attested_credential_data.credential_public_key),
          sign_count: auth_data.sign_count,
          label: if(label == "", do: default_label(), else: label)
        })

      {:noreply,
       socket
       |> assign(:credentials, Accounts.list_user_credentials(socket.assigns.user))
       |> assign(:reg_challenge, nil)
       |> put_flash(:info, "Passkey added.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not add that passkey.")}
    end
  end

  def handle_event("passkey_error", %{"message" => _m}, socket),
    do: {:noreply, put_flash(socket, :error, "Passkey registration was cancelled.")}

  def handle_event("delete_passkey", %{"id" => id}, socket) do
    Accounts.delete_credential(socket.assigns.user, String.to_integer(id))
    {:noreply, assign(socket, :credentials, Accounts.list_user_credentials(socket.assigns.user))}
  end

  defp default_label, do: "Passkey · " <> Calendar.strftime(DateTime.utc_now(), "%b %-d, %Y")
```

- [ ] **Step 4: Settings test for delete**

Add to `settings_live_test.exs` a test that seeds a credential (via `Accounts.create_credential`) and asserts the row renders and `delete_passkey` removes it (the create/register ceremony itself is covered by the Playwright e2e in Task 5, since it needs an authenticator).

```elixir
  test "lists and deletes passkeys", %{conn: conn, user: user} do
    {:ok, cred} =
      Newton.Accounts.create_credential(user, %{
        credential_id: <<9, 9, 9>>,
        public_key: :erlang.term_to_binary(%{1 => 2}),
        sign_count: 0,
        label: "My Laptop"
      })

    {:ok, view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "My Laptop"

    view |> element("button[phx-value-id='#{cred.id}']") |> render_click()
    refute render(view) =~ "My Laptop"
  end
```

- [ ] **Step 5: Run JS + Elixir tests**

Run: `cd assets && pnpm vitest run` and `mix test test/newton_web/live/admin/settings_live_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/js/webauthn.js assets/js/webauthn.test.js assets/js/hooks/passkey_register.js assets/js/admin.js lib/newton_web/live/admin/settings_live.ex test/newton_web/live/admin/settings_live_test.exs
git commit -m "$(cat <<'EOF'
Add passkey registration to the settings page

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Passwordless login (controller endpoints + conditional UI)

**Files:**
- Modify: `lib/newton_web/router.ex` (two passkey routes), `lib/newton_web/controllers/user_session_controller.ex`
- Create: `assets/js/hooks/passkey_authenticate.js`; Modify `assets/js/app.js`
- Modify: `lib/newton_web/live/user_live/login.ex` (conditional-UI hook + fallback button + `autocomplete`)
- Test: `test/newton_web/controllers/user_session_controller_test.exs`

- [ ] **Step 1: Routes**

In the public auth scope of `lib/newton_web/router.ex` (the `:browser` scope with `/login`), add:

```elixir
    get "/login/passkey/challenge", UserSessionController, :passkey_challenge
    post "/login/passkey", UserSessionController, :passkey_login
```

- [ ] **Step 2: Controller endpoints**

In `lib/newton_web/controllers/user_session_controller.ex`:

```elixir
  def passkey_challenge(conn, _params) do
    challenge = Newton.Webauthn.authentication_challenge()

    conn
    |> put_session(:passkey_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: challenge.rp_id,
      userVerification: "preferred"
    })
  end

  def passkey_login(conn, %{"id" => raw_id, "authenticatorData" => auth_data_b64,
                            "clientDataJSON" => cdj_b64, "signature" => sig_b64} = params) do
    challenge = get_session(conn, :passkey_challenge)

    with false <- is_nil(challenge),
         {:ok, cred_id} <- Base.url_decode64(raw_id, padding: false),
         %{} = cred <- Newton.Accounts.get_credential_by_external_id(cred_id),
         {:ok, auth_data_bin} <- Base.url_decode64(auth_data_b64, padding: false),
         {:ok, sig} <- Base.url_decode64(sig_b64, padding: false),
         {:ok, client_data} <- Base.url_decode64(cdj_b64, padding: false),
         {:ok, auth_data} <-
           Wax.authenticate(cred_id, auth_data_bin, sig, client_data, challenge,
             [{cred_id, Newton.Webauthn.load_key(cred.public_key)}]),
         true <- auth_data.sign_count >= cred.sign_count do
      {:ok, _} =
        Newton.Accounts.update_credential_sign_count(cred, auth_data.sign_count, DateTime.truncate(DateTime.utc_now(), :second))

      conn
      |> delete_session(:passkey_challenge)
      |> NewtonWeb.UserAuth.log_in_user(cred.user)
      |> json(%{ok: true, to: NewtonWeb.UserAuth.signed_in_path(conn)})
    else
      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Passkey authentication failed."})
    end
  end
```

(`params` also carries optional `userHandle`; unused for usernameless lookup-by-credential-id. Confirm the `Wax.authenticate/6` arg order against the Task 2 spike.)

- [ ] **Step 3: Controller tests (failure paths deterministic; success via e2e)**

In `test/newton_web/controllers/user_session_controller_test.exs` add:

```elixir
  describe "passkey endpoints" do
    test "challenge returns a base64url challenge and sets the session", %{conn: conn} do
      conn = get(conn, ~p"/login/passkey/challenge")
      assert %{"challenge" => ch, "rpId" => _} = json_response(conn, 200)
      assert is_binary(ch)
      assert get_session(conn, :passkey_challenge)
    end

    test "login rejects an unknown credential", %{conn: conn} do
      conn = get(conn, ~p"/login/passkey/challenge")

      conn =
        post(conn, ~p"/login/passkey", %{
          "id" => Base.url_encode64(<<0, 0, 0>>, padding: false),
          "authenticatorData" => "AA",
          "clientDataJSON" => "AA",
          "signature" => "AA"
        })

      assert json_response(conn, 401)
    end
  end
```

Run: `mix test test/newton_web/controllers/user_session_controller_test.exs` (write → fail → implement → pass).

- [ ] **Step 4: The PasskeyAuthenticate hook (conditional UI)**

Create `assets/js/hooks/passkey_authenticate.js`:

```js
import {bufToB64url, b64urlToBuf} from "../webauthn"

async function runCeremony(hook, mediation) {
  const res = await fetch("/login/passkey/challenge", {headers: {accept: "application/json"}})
  const {challenge, rpId, userVerification} = await res.json()
  const cred = await navigator.credentials.get({
    mediation,
    publicKey: {challenge: b64urlToBuf(challenge), rpId, userVerification, allowCredentials: []},
  })
  const token = document.querySelector("meta[name='csrf-token']").content
  const out = await fetch("/login/passkey", {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": token},
    body: JSON.stringify({
      id: bufToB64url(cred.rawId),
      authenticatorData: bufToB64url(cred.response.authenticatorData),
      clientDataJSON: bufToB64url(cred.response.clientDataJSON),
      signature: bufToB64url(cred.response.signature),
      userHandle: cred.response.userHandle ? bufToB64url(cred.response.userHandle) : null,
    }),
  })
  if (out.ok) {
    const {to} = await out.json()
    window.location.assign(to)
  }
}

export const PasskeyAuthenticate = {
  async mounted() {
    // Conditional UI: passkeys appear as autofill on the username field.
    if (window.PublicKeyCredential?.isConditionalMediationAvailable) {
      const ok = await PublicKeyCredential.isConditionalMediationAvailable().catch(() => false)
      if (ok) runCeremony(this, "conditional").catch(() => {})
    }
    // Fallback button (shown for browsers without conditional UI).
    const btn = document.getElementById("passkey-button")
    if (btn) btn.addEventListener("click", () => runCeremony(this, "optional").catch(() => {}))
  },
}
```

Register `PasskeyAuthenticate` in `assets/js/app.js` (public bundle) hooks map.

- [ ] **Step 5: Wire the login page**

In `lib/newton_web/live/user_live/login.ex`: change the email `<.input ... autocomplete="username">` to `autocomplete="username webauthn"`, attach the hook to a wrapper (`id="passkey-login" phx-hook="PasskeyAuthenticate"`), and add a fallback `<button type="button" id="passkey-button">Sign in with a passkey</button>` below the password form.

- [ ] **Step 6: Run the suites**

Run: `cd assets && pnpm vitest run` and `mix test` — PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/router.ex lib/newton_web/controllers/user_session_controller.ex assets/js/hooks/passkey_authenticate.js assets/js/app.js lib/newton_web/live/user_live/login.ex test/newton_web/controllers/user_session_controller_test.exs
git commit -m "$(cat <<'EOF'
Add passwordless passkey login with conditional UI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Full verification + Playwright virtual-authenticator e2e

- [ ] **Step 1: precommit**

Run: `mix precommit` — PASS (format, compile, credo, dialyzer, full `mix test`, JS suite). Fix findings (don't disable linters).

- [ ] **Step 2: e2e with a CDP virtual authenticator**

Build assets, start `PORT=4001`. Create `assets/passkey_e2e.mjs` that:
1. opens a CDP session, enables WebAuthn, and `addVirtualAuthenticator` with
   `{protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true, automaticPresenceSimulation: true}`;
2. logs in with the **password** (your local admin credentials), goes to `/admin/settings`, names + clicks "Add a passkey" — asserts a credential row appears (and the virtual authenticator now has a credential);
3. logs out, then on `/login` clicks the fallback "Sign in with a passkey" button — asserts it lands on `/admin` (logged in via passkey).

Run: `cd assets && node passkey_e2e.mjs`. Expected: registration row appears; passkey login reaches `/admin`.

- [ ] **Step 3: Clean up**

Remove `assets/passkey_e2e.mjs`, stop the PORT=4001 server, confirm `config/dev.exs` unchanged.

- [ ] **Step 4: Commit any verification fixes** (only if needed)

```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix issues found verifying passkey auth

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** settings + change-password (Task 1); Wax dep + config + credentials store (Task 2); register-over-socket (Task 3); passwordless login via controller endpoints + conditional UI + fallback button (Task 4); Playwright virtual-authenticator e2e (Task 5). Build sequencing matches the spec's.
- **Integration-risk handling:** the one uncertain area (exact Wax result struct fields) is pinned by the **Task 2 spike** before any ceremony code reads those fields (Tasks 3–4 note "confirmed by the spike"). The JS ceremonies are verified by the Task 5 virtual-authenticator e2e.
- **Type/name consistency:** `bufToB64url`/`b64urlToBuf` defined in Task 3 and imported in Task 4; `create_credential`/`list_user_credentials`/`get_credential_by_external_id`/`update_credential_sign_count`/`delete_credential` defined in Task 2 and used in Tasks 3–4; `Newton.Webauthn.{registration_challenge,authentication_challenge,dump_key,load_key}` defined in Task 2; the `passkey_create`/`passkey_registered`/`passkey_error` event names match between the hook (Task 3) and LiveView (Task 3); the `/login/passkey*` routes (Task 4) match the controller actions and the hook's fetch URLs.
- **Out of scope:** passkey-only/recovery codes, rename, AAGUID display, sudo-mode re-auth.
