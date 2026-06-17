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

        <Components.drawer_footer
          cancel_path={@cancel_path}
          deletable?={@editing?}
          delete_event="delete_gallery"
          delete_confirm="Delete this gallery and all its photos?"
        />
      </.form>
    </Components.drawer>
    """
  end
end
