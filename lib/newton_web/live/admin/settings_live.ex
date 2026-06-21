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
        <.form
          for={@password_form}
          id="password-form"
          phx-submit="save_password"
          class="flex flex-col gap-3"
        >
          <.input
            name="current_password"
            type="password"
            label="Current password"
            value=""
            autocomplete="current-password"
            errors={
              NewtonWeb.CoreComponents.translate_errors(@password_form.errors, :current_password)
            }
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <button
            type="submit"
            class="self-start rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white"
          >
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
