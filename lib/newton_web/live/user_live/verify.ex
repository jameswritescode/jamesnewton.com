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

          <.form
            :if={@show_recovery}
            for={%{}}
            action={~p"/login/verify/recovery"}
            method="post"
            class="mt-4 flex flex-col gap-2"
          >
            <label for="recovery-code" class="text-[0.78rem] text-(--admin-text-muted)">
              Recovery code
            </label>
            <input
              id="recovery-code"
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
          </.form>
        </div>

        <AdminLayouts.admin_flash_group flash={@flash} />
      </div>
    </div>
    """
  end
end
