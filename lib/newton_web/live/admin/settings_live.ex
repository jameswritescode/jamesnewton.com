defmodule NewtonWeb.Admin.SettingsLive do
  use NewtonWeb, :live_view

  alias Newton.Accounts
  alias Newton.OAuth
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts
  alias NewtonWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:user, user)
     |> assign(:timezone_form, timezone_form(user))
     |> assign(:password_form, password_form())
     |> assign(:credentials, Accounts.list_user_credentials(user))
     |> assign(:reg_challenge, nil)
     |> assign(:new_label, "")
     |> assign(:recovery_count, Accounts.count_unused_recovery_codes(user))
     |> assign(:new_recovery_codes, nil)
     |> assign(:authorized_clients, OAuth.list_authorized_clients())}
  end

  defp timezone_form(user), do: to_form(Accounts.User.timezone_changeset(user, %{}), as: :user)

  defp password_form, do: to_form(Accounts.change_user_password(%Accounts.User{}), as: :user)

  @impl true
  def handle_event("save_password", params, socket) do
    %{"current_password" => current, "user" => user_params} = params

    case Accounts.update_user_password(socket.assigns.user, current, user_params) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:password_form, password_form())
         |> put_flash(:info, "Password updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("save_timezone", %{"user" => params}, socket) do
    case Accounts.update_user_timezone(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:timezone_form, timezone_form(user))
         |> put_flash(:info, "Timezone updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :timezone_form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("set_label", %{"new_label" => label}, socket) do
    {:noreply, assign(socket, :new_label, label)}
  end

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
      authenticatorSelection: %{residentKey: "required", userVerification: "required"},
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
    %{"clientDataJSON" => cdj, "attestationObject" => att, "label" => label} = params

    challenge = socket.assigns.reg_challenge

    # Both the id and the key come from the attestation Wax just verified. The
    # client also sends `rawId`, but trusting it would let the browser name a
    # credential the attestation never covered.
    with {:ok, att_obj} <- Base.url_decode64(att, padding: false),
         {:ok, client_data} <- Base.url_decode64(cdj, padding: false),
         {:ok, {auth_data, _}} <- Wax.register(att_obj, client_data, challenge) do
      {:ok, _} =
        Accounts.create_credential(socket.assigns.user, %{
          credential_id: auth_data.attested_credential_data.credential_id,
          public_key:
            Newton.Webauthn.dump_key(auth_data.attested_credential_data.credential_public_key),
          sign_count: auth_data.sign_count,
          label: if(label == "", do: default_label(), else: label)
        })

      {:noreply,
       socket
       |> assign(:credentials, Accounts.list_user_credentials(socket.assigns.user))
       |> assign(:reg_challenge, nil)
       |> assign(:new_label, "")
       |> assign(:new_recovery_codes, nil)
       |> put_flash(:info, "Passkey added.")}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:reg_challenge, nil)
         |> put_flash(:error, "Could not add that passkey.")}
    end
  end

  def handle_event("passkey_error", %{"message" => _m}, socket),
    do: {:noreply, put_flash(socket, :error, "Passkey registration was cancelled.")}

  def handle_event("generate_recovery_codes", _params, socket) do
    with_fresh_sudo(socket, fn socket ->
      codes = Accounts.generate_recovery_codes(socket.assigns.user)

      socket
      |> assign(:new_recovery_codes, codes)
      |> assign(:recovery_count, length(codes))
      |> put_flash(:info, "Recovery codes generated. Save them now — they won't be shown again.")
    end)
  end

  def handle_event("delete_passkey", %{"id" => id}, socket) do
    with_fresh_sudo(socket, fn socket ->
      Accounts.delete_credential(socket.assigns.user, String.to_integer(id))
      assign(socket, :credentials, Accounts.list_user_credentials(socket.assigns.user))
    end)
  end

  def handle_event("revoke_client", %{"id" => id}, socket) do
    with_fresh_sudo(socket, fn socket ->
      entry =
        Enum.find(socket.assigns.authorized_clients, &(&1.client.id == String.to_integer(id)))

      socket =
        if entry && OAuth.revoke_client_grants(entry.client) > 0,
          do: put_flash(socket, :info, "#{entry.client.client_name} revoked."),
          else: socket

      assign(socket, :authorized_clients, OAuth.list_authorized_clients())
    end)
  end

  # `:require_sudo_mode` only runs at mount, so a tab left open past the window
  # could still mint recovery codes or strip passkeys. Re-check at event time.
  defp with_fresh_sudo(socket, fun) do
    if Accounts.sudo_mode?(socket.assigns.user, -10) do
      {:noreply, fun.(socket)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Confirm it's you to manage security settings.")
       |> push_navigate(to: ~p"/login/confirm-access")}
    end
  end

  defp default_label, do: "Passkey · " <> Calendar.strftime(DateTime.utc_now(), "%b %-d, %Y")

  defp format_day(nil), do: "—"
  defp format_day(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:settings}>
      <Components.page_header title="Settings" />

      <section class="mb-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Timezone</h2>
        <.form for={@timezone_form} id="timezone-form" phx-submit="save_timezone">
          <Components.field
            field={@timezone_form[:timezone]}
            type="select"
            label="Analytics and dashboard render in this timezone"
            options={Tzdata.zone_list()}
          />
          <div class="mt-3">
            <Components.button type="submit">Save timezone</Components.button>
          </div>
        </.form>
      </section>

      <section class="mb-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Change password</h2>
        <.form
          for={@password_form}
          id="password-form"
          phx-submit="save_password"
          class="flex flex-col gap-3"
        >
          <Components.field
            name="current_password"
            type="password"
            label="Current password"
            value=""
            autocomplete="current-password"
            errors={translate_errors(@password_form.errors, :current_password)}
          />
          <Components.field
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
          />
          <Components.field
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <Components.button type="submit">Update password</Components.button>
        </.form>
      </section>

      <section class="max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Passkeys</h2>

        <ul :if={@credentials != []} id="passkey-list" class="mb-4 flex flex-col gap-2">
          <li
            :for={c <- @credentials}
            id={"passkey-#{c.id}"}
            class="flex items-center justify-between rounded-md border border-(--admin-border) px-3 py-2"
          >
            <div>
              <div class="text-[0.85rem] text-(--admin-text)">{c.label}</div>
              <div class="text-[0.72rem] text-(--admin-text-subtle)">
                Added {format_day(c.inserted_at)} · Last used {format_day(c.last_used_at)}
              </div>
            </div>
            <Components.button
              variant="secondary"
              phx-click="delete_passkey"
              phx-value-id={c.id}
              data-confirm="Remove this passkey?"
            >
              Remove
            </Components.button>
          </li>
        </ul>

        <p :if={@credentials == []} class="mb-4 text-[0.82rem] text-(--admin-text-subtle)">
          No passkeys yet. Your password still works as a sign-in method.
        </p>

        <form phx-change="set_label" class="flex flex-col gap-3">
          <Components.field
            type="text"
            name="new_label"
            value={@new_label}
            label="New passkey name"
            placeholder="e.g. My laptop"
          />
          <div id="passkey-register" phx-hook="PasskeyRegister" data-label={@new_label}>
            <Components.button phx-click="start_registration">Add a passkey</Components.button>
          </div>
        </form>
      </section>

      <section :if={@credentials != []} class="mt-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Recovery codes</h2>
        <p class="mb-3 text-[0.82rem] text-(--admin-text-subtle)">
          Use a recovery code to sign in if you lose access to your passkey.
        </p>

        <div :if={@new_recovery_codes} class="mb-3">
          <div
            id="recovery-codes"
            class="grid grid-cols-2 gap-x-6 gap-y-1 rounded-md border border-(--admin-border) bg-(--admin-bg) p-3 font-mono text-[0.85rem] text-(--admin-text)"
          >
            <span :for={code <- @new_recovery_codes}>{code}</span>
          </div>
          <p class="mt-1 text-[0.72rem] text-(--admin-text-subtle)">
            Save these now — they won't be shown again.
          </p>
        </div>

        <p :if={!@new_recovery_codes} class="mb-3 text-[0.82rem] text-(--admin-text-muted)">
          {@recovery_count} of 10 codes remaining.
        </p>

        <Components.button phx-click="generate_recovery_codes">
          {if @recovery_count > 0, do: "Regenerate recovery codes", else: "Generate recovery codes"}
        </Components.button>
      </section>

      <section class="mt-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Connected apps</h2>

        <ul :if={@authorized_clients != []} id="connected-apps" class="flex flex-col gap-2">
          <li
            :for={entry <- @authorized_clients}
            id={"connected-app-#{entry.client.id}"}
            class="flex items-center justify-between rounded-md border border-(--admin-border) px-3 py-2"
          >
            <div>
              <div class="text-[0.85rem] text-(--admin-text)">{entry.client.client_name}</div>
              <div class="text-[0.72rem] text-(--admin-text-subtle)">
                First connected {format_day(entry.first_connected_at)} · Last active {format_day(
                  entry.last_active_at
                )} · {entry.grant_count} {if(entry.grant_count == 1, do: "grant", else: "grants")}
              </div>
            </div>
            <Components.button
              variant="secondary"
              phx-click="revoke_client"
              phx-value-id={entry.client.id}
              data-confirm={"Revoke #{entry.client.client_name}'s access?"}
            >
              Revoke
            </Components.button>
          </li>
        </ul>

        <p
          :if={@authorized_clients == []}
          id="connected-apps-empty"
          class="text-[0.82rem] text-(--admin-text-subtle)"
        >
          No apps have access.
        </p>
      </section>
    </Layouts.admin>
    """
  end
end
