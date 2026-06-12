defmodule NewtonWeb.Admin.GalleryLive.Components do
  @moduledoc "Shared gallery admin components used by both the list and the in-gallery manager."
  use NewtonWeb, :html

  alias NewtonWeb.Admin.Components

  @doc """
  The gallery settings drawer (title, slug, caption, taken-on, delete). Driven by
  the host LiveView's `validate_settings`/`save_settings`/`delete_gallery`/
  `close_settings` events; `cancel_path` patches back to the host's own URL.
  """
  attr :form, :map, required: true
  attr :editing?, :boolean, required: true
  attr :cancel_path, :string, required: true

  def settings_drawer(assigns) do
    ~H"""
    <Components.drawer id="gallery-drawer" on_close="close_settings">
      <:title>{if @editing?, do: "Edit gallery", else: "New gallery"}</:title>

      <.form
        for={@form}
        id="gallery-form"
        phx-change="validate_settings"
        phx-submit="save_settings"
        class="flex flex-col gap-3"
      >
        <Components.field field={@form[:title]} label="Title" />
        <Components.field field={@form[:slug]} label="Slug" />
        <Components.field field={@form[:caption]} type="textarea" label="Caption" rows="2" />
        <Components.field field={@form[:taken_on]} type="date" label="Taken on" />

        <div class="mt-2 flex items-center gap-2">
          <button
            :if={@editing?}
            type="button"
            phx-click="delete_gallery"
            data-confirm="Delete this gallery and all its photos?"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
          >
            Delete
          </button>
          <div class="flex-1"></div>
          <.link
            patch={@cancel_path}
            class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
          >
            Cancel
          </.link>
          <button
            type="submit"
            class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Save
          </button>
        </div>
      </.form>
    </Components.drawer>
    """
  end
end
