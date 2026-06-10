defmodule NewtonWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use NewtonWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc "The site header used on every page."
  def site_header(assigns) do
    ~H"""
    <header class="site-header">
      <a href={~p"/"} class="site-name">James Newton</a>
    </header>
    """
  end

  @doc """
  The app layout. Wraps page content; `inner_block` is rendered inside `<main>`.
  """
  attr :flash, :map, default: %{}

  attr :current_scope, :any,
    default: nil,
    doc: "accepted from auth LiveViews; unused by the public layout"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.site_header />
    <main id="main" class="transition-fade">
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  @doc "Shows the flash group with standard titles and content."
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
