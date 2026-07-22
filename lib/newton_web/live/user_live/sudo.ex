defmodule NewtonWeb.UserLive.Sudo do
  use NewtonWeb, :live_view

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
          <h1 class="text-[1.1rem] font-semibold text-(--admin-text)">Confirm it's you</h1>
          <p class="mt-1 mb-5 text-[0.82rem] text-(--admin-text-subtle)">
            Managing security settings needs a fresh sign-in.
          </p>

          <.form
            for={@form}
            id="sudo_form"
            action={~p"/login/confirm-access"}
            method="post"
            class="flex flex-col gap-3"
          >
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
                required
                phx-mounted={JS.focus()}
                class={@field_class}
              />
            </div>

            <button
              type="submit"
              class="mt-2 w-full rounded-md bg-(--admin-accent) px-3 py-2 text-[0.85rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Confirm
            </button>
          </.form>

          <div class="mt-4">
            <button
              id="sudo-passkey-button"
              type="button"
              phx-hook="PasskeySudo"
              class="w-full rounded-md border border-(--admin-border) px-3 py-2 text-[0.85rem] text-(--admin-text) hover:border-(--admin-accent)"
            >
              Use a passkey instead
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, to_form(%{}, as: :user))}
  end
end
