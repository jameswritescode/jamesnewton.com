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

  def open_graph_config(conn) do
    SEO.OpenGraph.build(
      site_name: "James Newton",
      type: :website,
      title: "James Newton",
      description: "Software & Photography",
      url: Phoenix.Controller.current_url(conn),
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

  # The card endpoint only serves published posts. Lives here because the Post
  # OpenGraph and Twitter defimpls cannot share a private helper.
  def post_image_url(%{published_at: nil}), do: url(~p"/og-default.png")
  def post_image_url(post), do: url(~p"/og/posts/#{post.slug}")
end

defmodule NewtonWeb.SEO.Page do
  defstruct [:title, :description, :path, :image, json_ld: []]
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

  defp image(%{published_at: nil} = post) do
    SEO.OpenGraph.Image.build(url: NewtonWeb.SEO.post_image_url(post))
  end

  defp image(post) do
    SEO.OpenGraph.Image.build(
      url: NewtonWeb.SEO.post_image_url(post),
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
    SEO.Twitter.build(
      title: post.title,
      description: post.excerpt,
      image: NewtonWeb.SEO.post_image_url(post)
    )
  end
end

defimpl SEO.JSONLD.Build, for: Newton.Blog.Post do
  use NewtonWeb, :verified_routes

  def build(%{published_at: nil}, _conn), do: nil

  def build(post, _conn) do
    SEO.JSONLD.Article.build(%{
      headline: post.title,
      description: post.excerpt,
      date_published: post.published_at,
      author: SEO.JSONLD.Person.build(%{name: "James Newton", url: url(~p"/")}),
      image: NewtonWeb.SEO.post_image_url(post),
      main_entity_of_page: url(~p"/posts/#{post.slug}")
    })
  end
end

defimpl SEO.OpenGraph.Build, for: NewtonWeb.SEO.Page do
  def build(%{image: nil} = page, _conn) do
    SEO.OpenGraph.build(title: page.title, description: page.description)
  end

  def build(page, _conn) do
    SEO.OpenGraph.build(
      title: page.title,
      description: page.description,
      image:
        SEO.OpenGraph.Image.build(
          url: NewtonWeb.Endpoint.url() <> page.image,
          width: 1200,
          height: 630,
          alt: page.title
        )
    )
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
  def build(%{image: nil} = page, _conn) do
    SEO.Twitter.build(title: page.title, description: page.description)
  end

  def build(page, _conn) do
    SEO.Twitter.build(
      title: page.title,
      description: page.description,
      image: NewtonWeb.Endpoint.url() <> page.image
    )
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
