defmodule NewtonWeb.Admin.Components do
  @moduledoc """
  Reusable admin UI building blocks shared across the admin LiveViews:
  a right-hand slide-over `drawer/1` and an admin-themed form `field/1`.
  """
  use NewtonWeb, :html

  @doc """
  A right-hand slide-over drawer. The caller renders it conditionally
  (`:if={@open?}`) and passes `on_close` — a `Phoenix.LiveView.JS` command or an
  event name — which fires on the close button, Escape, and a click outside.
  """
  attr :id, :string, required: true
  attr :on_close, :any, required: true
  slot :title, required: true
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <div
      id={@id}
      phx-window-keydown={@on_close}
      phx-key="Escape"
      phx-click-away={@on_close}
      phx-mounted={
        JS.transition(
          {"transition-transform ease-out duration-200", "translate-x-full", "translate-x-0"},
          time: 200
        )
      }
      phx-remove={
        JS.transition(
          {"transition-transform ease-in duration-200", "translate-x-0", "translate-x-full"},
          time: 200
        )
      }
      class="fixed inset-y-0 right-0 z-20 flex w-80 max-w-[calc(100vw-3rem)] flex-col gap-4 overflow-y-auto border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
    >
      <div class="flex items-center justify-between">
        <span class="text-[0.9rem] font-semibold">{render_slot(@title)}</span>
        <button
          type="button"
          phx-click={@on_close}
          aria-label="Close"
          class="text-(--admin-text-subtle) hover:text-(--admin-text)"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </button>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A form field styled for the admin theme. Wraps the core `<.input>` so drawer
  fields share the post editor's surface/border/text colors in light and dark.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :options, :list, default: []
  attr :rest, :global, include: ~w(rows placeholder autocomplete)

  def field(assigns) do
    ~H"""
    <.input
      field={@field}
      type={@type}
      label={@label}
      options={@options}
      class={field_class()}
      {@rest}
    />
    """
  end

  defp field_class do
    "w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-3 py-2 text-[0.85rem] text-(--admin-text) focus:border-(--admin-accent) focus:outline-none"
  end
end
