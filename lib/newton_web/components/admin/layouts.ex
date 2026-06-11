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
  @built [:dashboard, :posts, :reading]

  attr :flash, :map, default: %{}
  attr :current, :atom, required: true, doc: "the active section key"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, sections: @sections, built: @built)

    ~H"""
    <div class="flex min-h-screen">
      <aside class="sticky top-0 flex h-screen w-56 shrink-0 flex-col border-r border-(--admin-border) bg-(--admin-sidebar) px-3 py-[1.1rem]">
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

        <div class="mt-[0.6rem] border-t border-(--admin-border) pt-[0.6rem]">
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

      <main id="admin-main" class="max-w-6xl flex-1 px-10 py-8">
        <Layouts.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>
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
