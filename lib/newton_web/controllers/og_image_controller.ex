defmodule NewtonWeb.OgImageController do
  @moduledoc """
  Renders a post's Open Graph card. Rendered PNGs are memoized per
  `{slug, updated_at}` (see Newton.SocialCard.Cache) so this public endpoint
  can't be looped to burn libvips CPU, and stay fresh when a post is edited.
  Also cached at the edge/browser via HTTP headers.
  """
  use NewtonWeb, :controller

  alias Newton.Blog
  alias Newton.SocialCard

  @cache_control "public, max-age=3600"

  def show(conn, %{"slug" => slug}) do
    post = Blog.get_published_post!(slug)

    render =
      SocialCard.Cache.fetch(slug, post.updated_at, fn ->
        SocialCard.post_card(%{
          title: post.title,
          published_on: post.published_at && DateTime.to_date(post.published_at),
          reading_time: post.reading_time || 1
        })
      end)

    case render do
      {:ok, png} ->
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", @cache_control)
        |> send_resp(200, png)

      {:error, _reason} ->
        # Rendering should not fail in practice; fall back to the static card
        # rather than 500 so the crawler still gets an image.
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", @cache_control)
        |> send_file(200, Path.join(:code.priv_dir(:newton), "static/og-default.png"))
    end
  end
end
