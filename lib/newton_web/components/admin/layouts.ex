defmodule NewtonWeb.Admin.Layouts do
  @moduledoc """
  Neutral admin shell. Wrap admin LiveView content with `<Admin.Layouts.admin>`.
  Distinct from the public `NewtonWeb.Layouts` (warm palette) — the admin uses
  Tailwind + daisyUI in functional, neutral colors.
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
    <div class="flex min-h-screen bg-zinc-100 text-zinc-900">
      <aside class="w-56 shrink-0 bg-zinc-900 px-3 py-5 text-zinc-100">
        <div class="px-2 pb-4 text-lg font-semibold tracking-tight text-white">newton</div>
        <nav class="flex flex-col gap-1">
          <.nav_item
            :for={section <- @sections}
            section={section}
            current={@current}
            built={section.key in @built}
          />
        </nav>
      </aside>

      <main id="admin-main" class="flex-1 px-8 py-6">
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
    <span class="cursor-default rounded-lg px-3 py-2 text-sm text-zinc-500">
      {@section.label}
    </span>
    """
  end

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@section.path}
      class={[
        "rounded-lg px-3 py-2 text-sm no-underline transition-colors",
        @section.key == @current && "bg-indigo-600 text-white",
        @section.key != @current && "text-zinc-300 hover:bg-zinc-800"
      ]}
    >
      {@section.label}
    </.link>
    """
  end
end
