defmodule NewtonWeb.UserLive.Login do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts, as: AdminLayouts

  @field_class "w-full rounded-md border border-(--admin-border) bg-(--admin-bg) px-3 py-2 text-[0.85rem] text-(--admin-text) focus:border-(--admin-accent) focus:outline-none"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :field_class, @field_class)

    ~H"""
    <div class="flex min-h-screen items-center justify-center px-4">
      <div class="w-full max-w-sm">
        <div class="mb-6 flex items-center justify-center gap-2 text-[1.05rem] font-semibold tracking-tight text-(--admin-text)">
          <span class="size-2.5 rounded-full bg-(--admin-accent)"></span> newton
        </div>

        <div class="rounded-xl border border-(--admin-border) bg-(--admin-surface) p-6 shadow-sm">
          <h1 class="text-[1.1rem] font-semibold text-(--admin-text)">Sign in</h1>
          <p class="mt-1 mb-5 text-[0.82rem] text-(--admin-text-subtle)">
            Sign in to manage the site.
          </p>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/login"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
            class="flex flex-col gap-3"
          >
            <div>
              <label for={f[:email].id} class="mb-1 block text-[0.78rem] text-(--admin-text-muted)">
                Email
              </label>
              <.input
                field={f[:email]}
                type="email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
                class={@field_class}
              />
            </div>

            <div>
              <label
                for={@form[:password].id}
                class="mb-1 block text-[0.78rem] text-(--admin-text-muted)"
              >
                Password
              </label>
              <.input
                field={@form[:password]}
                type="password"
                autocomplete="current-password"
                spellcheck="false"
                required
                class={@field_class}
              />
            </div>

            <button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              class="mt-2 w-full rounded-md bg-(--admin-accent) px-3 py-2 text-[0.85rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Sign in
            </button>
          </.form>
        </div>
      </div>

      <AdminLayouts.admin_flash_group flash={@flash} />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
