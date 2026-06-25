defmodule NewtonWeb.SiteComponents do
  @moduledoc "Function components built from the prototype's component language."
  use Phoenix.Component

  @doc "Primary middot-separated nav."
  def site_nav(assigns) do
    ~H"""
    <nav class="site-nav" aria-label="Primary">
      <a href="/posts">Posts</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href="/photos">Photos</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href="/reading">Reading</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href="/resume">Resume</a>
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <%!-- Full navigation (no Swup) so the /links takeover replaces the whole page,
            rather than swapping #main and leaving the site header behind. --%>
      <a href="/links" data-no-swup>Links</a>
    </nav>
    """
  end

  @doc "Feed wrapper with an optional uppercase heading."
  attr :heading, :string, default: nil
  slot :inner_block, required: true

  def feed(assigns) do
    ~H"""
    <section class="feed">
      <h2 :if={@heading} class="feed-heading">{@heading}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  A single feed entry. `href` makes it a link; omit for a static block.
  `date` is a preformatted date string. `variant`: nil (post), "book", or "photo".
  """
  attr :href, :string, default: nil
  attr :id, :string, default: nil
  attr :date, :string, default: nil
  attr :variant, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def feed_item(assigns) do
    assigns =
      assign(assigns, :class, ["feed-item", assigns.variant && "feed-item--#{assigns.variant}"])

    ~H"""
    <a :if={@href} href={@href} id={@id} class={@class} {@rest}>
      <time :if={@date} class="feed-item-date">{@date}</time>
      {render_slot(@inner_block)}
    </a>
    <div :if={!@href} id={@id} class={@class} {@rest}>
      <time :if={@date} class="feed-item-date">{@date}</time>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
