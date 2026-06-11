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
  @built [:dashboard]

  attr :flash, :map, default: %{}
  attr :current, :atom, required: true, doc: "the active section key"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, sections: @sections, built: @built)

    ~H"""
    <div class="admin-shell">
      <aside class="admin-sidebar">
        <div class="admin-brand">
          <span class="admin-brand-dot"></span> newton
        </div>

        <nav class="admin-nav">
          <.nav_item
            :for={section <- @sections}
            section={section}
            current={@current}
            built={section.key in @built}
          />
        </nav>

        <div class="admin-sidebar-footer">
          <button
            id="admin-theme-toggle"
            type="button"
            class="admin-theme-toggle"
            phx-hook="AdminTheme"
            aria-label="Toggle light or dark theme"
          >
            <.icon name="hero-sun-mini" class="admin-when-light size-4" />
            <.icon name="hero-moon-mini" class="admin-when-dark size-4" />
            <span class="admin-when-light">Light</span>
            <span class="admin-when-dark">Dark</span>
          </button>
        </div>
      </aside>

      <main id="admin-main" class="admin-main">
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
    <span class="admin-nav-link is-disabled">{@section.label}</span>
    """
  end

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@section.path}
      class={["admin-nav-link", @section.key == @current && "is-active"]}
    >
      {@section.label}
    </.link>
    """
  end
end
