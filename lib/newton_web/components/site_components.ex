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
    </nav>
    """
  end
end
