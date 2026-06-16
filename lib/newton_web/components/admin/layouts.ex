defmodule NewtonWeb.Admin.Layouts do
  @moduledoc """
  Neutral admin shell. Wrap admin LiveView content with `<Admin.Layouts.admin>`.
  Distinct from the public `NewtonWeb.Layouts` (warm palette) — the admin is a
  Linear-inspired, token-driven surface (see `assets/css/admin.css`) with light
  and dark themes.
  """
  use NewtonWeb, :html

  @sections [
    %{key: :dashboard, label: "Dashboard", path: "/admin"},
    %{key: :posts, label: "Posts", path: "/admin/posts"},
    %{key: :reading, label: "Reading", path: "/admin/reading"},
    %{key: :photos, label: "Photos", path: "/admin/photos"}
  ]

  # Sections whose routes exist today render as links; the rest are inert
  # placeholders until their own plans land.
  @built [:dashboard, :posts, :reading, :photos]

  attr :flash, :map, default: %{}
  attr :current, :atom, required: true, doc: "the active section key"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, sections: @sections, built: @built)

    ~H"""
    <div class="flex min-h-screen">
      <aside
        id="admin-sidebar"
        class="fixed inset-y-0 left-0 z-40 flex h-screen w-56 -translate-x-full flex-col border-r border-(--admin-border) bg-(--admin-sidebar) px-3 py-[1.1rem] transition-transform duration-200 md:sticky md:top-0 md:translate-x-0 md:shrink-0 md:transition-none"
      >
        <div class="flex items-center gap-2 px-[0.6rem] pb-[1.1rem] text-[0.95rem] font-semibold tracking-tight">
          <span class="size-2 rounded-full bg-(--admin-accent)"></span> newton
        </div>

        <nav class="flex flex-1 flex-col gap-0.5">
          <.nav_item
            :for={section <- @sections}
            section={section}
            current={@current}
            built={section.key in @built}
          />
        </nav>

        <div class="mt-[0.6rem] flex flex-col gap-0.5 border-t border-(--admin-border) pt-[0.6rem]">
          <.link
            href={~p"/"}
            class="flex items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) no-underline transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" /> View site
          </.link>
          <.link
            href={~p"/logout"}
            method="delete"
            class="flex items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) no-underline transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-arrow-right-start-on-rectangle-mini" class="size-4" /> Log out
          </.link>
          <button
            id="admin-theme-toggle"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
            phx-hook="AdminTheme"
            aria-label="Toggle light or dark theme"
          >
            <.icon name="hero-sun-mini" class="size-4 admin-dark:hidden" />
            <.icon name="hero-moon-mini" class="hidden size-4 admin-dark:inline-flex" />
            <span class="admin-dark:hidden">Light</span>
            <span class="hidden admin-dark:inline">Dark</span>
          </button>
        </div>
      </aside>

      <div id="admin-sidebar-backdrop" class="fixed inset-0 z-30 hidden bg-black/40 md:hidden"></div>

      <div class="flex min-w-0 flex-1 flex-col">
        <header class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-sidebar) px-4 py-3 md:hidden">
          <button
            id="admin-nav-toggle"
            type="button"
            phx-hook="AdminNav"
            aria-label="Open menu"
            aria-controls="admin-sidebar"
            aria-expanded="false"
            class="rounded-md p-1 text-(--admin-text-muted) hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <span class="flex items-center gap-2 text-[0.95rem] font-semibold tracking-tight">
            <span class="size-2 rounded-full bg-(--admin-accent)"></span> newton
          </span>
          <div class="flex-1"></div>
          <button
            id="admin-theme-toggle-mobile"
            type="button"
            class="rounded-md p-1 text-(--admin-text-muted) hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
            phx-hook="AdminTheme"
            aria-label="Toggle light or dark theme"
          >
            <.icon name="hero-sun-mini" class="size-5 admin-dark:hidden" />
            <.icon name="hero-moon-mini" class="hidden size-5 admin-dark:inline-flex" />
          </button>
        </header>

        <main id="admin-main" class="max-w-6xl flex-1 px-4 py-8 md:px-10">
          {render_slot(@inner_block)}
        </main>
      </div>
      <.admin_flash_group flash={@flash} />
    </div>
    """
  end

  attr :section, :map, required: true
  attr :current, :atom, required: true
  attr :built, :boolean, required: true

  defp nav_item(%{built: false} = assigns) do
    ~H"""
    <span class="rounded-md px-[0.6rem] py-[0.4rem] text-[0.825rem] text-(--admin-text-subtle)">
      {@section.label}
    </span>
    """
  end

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@section.path}
      class={[
        "flex items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.825rem] no-underline transition-colors",
        @section.key == @current && "bg-(--admin-accent-soft) font-medium text-(--admin-accent)",
        @section.key != @current &&
          "text-(--admin-text-muted) hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
      ]}
    >
      {@section.label}
    </.link>
    """
  end

  @doc "Admin flash toasts: token-styled, stacked at the bottom-right."
  attr :flash, :map, required: true

  def admin_flash_group(assigns) do
    ~H"""
    <div
      id="admin-flash-group"
      aria-live="polite"
      class="fixed bottom-4 right-4 z-50 flex flex-col items-end gap-2"
    >
      <.admin_flash kind={:info} flash={@flash} />
      <.admin_flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :flash, :map, required: true

  defp admin_flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"admin-flash-#{@kind}"}
      role="alert"
      phx-click={
        JS.push("lv:clear-flash", value: %{key: @kind})
        |> JS.hide(
          to: "#admin-flash-#{@kind}",
          transition:
            {"transition-all duration-200 ease-in", "opacity-100", "opacity-0 translate-y-1"}
        )
      }
      class={[
        "flex w-80 cursor-pointer items-center gap-3 rounded-lg border bg-(--admin-surface) p-3 text-[0.82rem] shadow-lg",
        @kind == :info && "border-(--admin-border) text-(--admin-text)",
        @kind == :error && "border-red-500/40 text-red-600 admin-dark:text-red-400"
      ]}
    >
      <.icon
        name={if @kind == :info, do: "hero-check-circle-mini", else: "hero-exclamation-circle-mini"}
        class={[
          "size-4 shrink-0",
          @kind == :info && "text-(--admin-accent)",
          @kind == :error && "text-red-500"
        ]}
      />
      <span class="flex-1">{msg}</span>
    </div>
    """
  end

  @doc "A pill badge for a post's publish status (:draft / :published / :scheduled)."
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[0.7rem] font-medium",
      @status == :draft && "border border-(--admin-border-strong) text-(--admin-text-subtle)",
      @status != :draft && "bg-(--admin-accent-soft) text-(--admin-accent)"
    ]}>
      {@status}
    </span>
    """
  end

  @doc "A pill badge for a reading entry's status."
  attr :status, :atom, required: true

  def reading_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[0.7rem] font-medium",
      @status in [:reading, :listening] && "bg-(--admin-accent-soft) text-(--admin-accent)",
      @status in [:read, :listened] &&
        "border border-(--admin-border-strong) text-(--admin-text-subtle)"
    ]}>
      {@status}
    </span>
    """
  end
end
