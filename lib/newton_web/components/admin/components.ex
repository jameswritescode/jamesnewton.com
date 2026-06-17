defmodule NewtonWeb.Admin.Components do
  @moduledoc """
  Reusable admin UI building blocks shared across the admin LiveViews:
  a right-hand slide-over `drawer/1` and an admin-themed form `field/1`, plus a
  `delete_button/1` and a `drawer_footer/1` action row.
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

  @doc "Consistent destructive button used in admin edit drawers."
  attr :event, :string, required: true
  attr :id, :any, default: nil
  attr :confirm, :string, required: true
  attr :label, :string, default: "Delete"

  def delete_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@id}
      data-confirm={@confirm}
      class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
    >
      {@label}
    </button>
    """
  end

  @doc """
  The shared edit-drawer footer: pinned to the bottom of the drawer with a top
  divider (full-bleed via `-mx-5` to cancel the drawer's padding). An optional
  Delete on the left, a spacer, an optional Cancel link, then the caller's primary
  action(s) in the slot (a `save_button`, or the post publish toggles).
  """
  attr :cancel_path, :string, default: nil
  attr :deletable?, :boolean, default: false
  attr :delete_event, :string, default: nil
  attr :delete_id, :any, default: nil
  attr :delete_confirm, :string, default: nil
  slot :inner_block, required: true

  def drawer_footer(assigns) do
    ~H"""
    <div class="mt-auto -mx-5 flex items-center gap-2 border-t border-(--admin-border) px-5 pt-4">
      <.delete_button
        :if={@deletable?}
        event={@delete_event}
        id={@delete_id}
        confirm={@delete_confirm}
      />
      <div class="flex-1"></div>
      <.link
        :if={@cancel_path}
        patch={@cancel_path}
        class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
      >
        Cancel
      </.link>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "The primary submit button used in edit-drawer footers."
  attr :label, :string, default: "Save"

  def save_button(assigns) do
    ~H"""
    <button
      type="submit"
      class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
    >
      {@label}
    </button>
    """
  end

  defp field_class do
    "w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-3 py-2 text-[0.85rem] text-(--admin-text) focus:border-(--admin-accent) focus:outline-none"
  end
end
