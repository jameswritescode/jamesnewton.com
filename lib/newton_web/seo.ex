defmodule NewtonWeb.SEO do
  use NewtonWeb, :verified_routes

  use SEO,
    json_library: Jason,
    site: &__MODULE__.site_config/1,
    open_graph: &__MODULE__.open_graph_config/1,
    twitter: &__MODULE__.twitter_config/1

  def site_config(_conn) do
    SEO.Site.build(
      default_title: "James Newton",
      title_prefix: NewtonWeb.Layouts.title_prefix(),
      description: "Software & Photography"
    )
  end

  def open_graph_config(_conn) do
    SEO.OpenGraph.build(
      site_name: "James Newton",
      type: :website,
      image: SEO.OpenGraph.Image.build(url: url(~p"/og-default.png"))
    )
  end

  def twitter_config(_conn) do
    SEO.Twitter.build(
      card: :summary_large_image,
      title: "James Newton",
      description: "Software & Photography",
      image: url(~p"/og-default.png")
    )
  end
end

defmodule NewtonWeb.SEO.Page do
  defstruct [:title, :description, :path, json_ld: []]
end

defimpl SEO.OpenGraph.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.OpenGraph.build(
      title: post.title,
      description: post.excerpt,
      url: url(~p"/posts/#{post.slug}"),
      detail: SEO.OpenGraph.Article.build(published_time: post.published_at),
      image: image(post)
    )
  end

  defp image(%{published_at: nil}) do
    SEO.OpenGraph.Image.build(url: url(~p"/og-default.png"))
  end

  defp image(post) do
    SEO.OpenGraph.Image.build(
      url: url(~p"/og/posts/#{post.slug}"),
      width: 1200,
      height: 630,
      alt: post.title
    )
  end
end

defimpl SEO.Site.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.Site.build(
      title: post.title,
      description: post.excerpt,
      canonical_url: url(~p"/posts/#{post.slug}")
    )
  end
end

defimpl SEO.Twitter.Build, for: Newton.Blog.Post do
  def build(post, _conn) do
    SEO.Twitter.build(title: post.title, description: post.excerpt)
  end
end

defimpl SEO.JSONLD.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(post, _conn) do
    SEO.JSONLD.Article.build(%{
      headline: post.title,
      description: post.excerpt,
      date_published: post.published_at,
      author: SEO.JSONLD.Person.build(%{name: "James Newton", url: url(~p"/")}),
      main_entity_of_page: url(~p"/posts/#{post.slug}")
    })
  end
end

defimpl SEO.OpenGraph.Build, for: NewtonWeb.SEO.Page do
  def build(page, _conn) do
    SEO.OpenGraph.build(title: page.title, description: page.description)
  end
end

defimpl SEO.Site.Build, for: NewtonWeb.SEO.Page do
  def build(page, _conn) do
    SEO.Site.build(
      title: page.title,
      description: page.description,
      canonical_url: NewtonWeb.Endpoint.url() <> page.path
    )
  end
end

defimpl SEO.Twitter.Build, for: NewtonWeb.SEO.Page do
  def build(page, _conn) do
    SEO.Twitter.build(title: page.title, description: page.description)
  end
end

defimpl SEO.JSONLD.Build, for: NewtonWeb.SEO.Page do
  use NewtonWeb, :verified_routes

  def build(%{path: "/"} = page, _conn) do
    person = SEO.JSONLD.Person.build(%{name: "James Newton", url: url(~p"/")})

    [
      SEO.JSONLD.WebSite.build(%{
        name: "James Newton",
        url: url(~p"/"),
        description: page.description
      }),
      person
    ]
  end

  def build(_page, _conn), do: nil
end
