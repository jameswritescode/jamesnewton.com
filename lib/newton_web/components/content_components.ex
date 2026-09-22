defmodule NewtonWeb.ContentComponents do
  @moduledoc "Shared public content chrome (the article/body skeleton)."
  use Phoenix.Component

  attr :title, :string, required: true
  attr :body_html, :string, required: true
  slot :byline

  def content_article(assigns) do
    ~H"""
    <article class="post">
      <header>
        <h1 class="post-title">{@title}</h1>
        {render_slot(@byline)}
      </header>

      <section class="post-body">
        {Phoenix.HTML.raw(@body_html)}
      </section>
    </article>
    """
  end
end
