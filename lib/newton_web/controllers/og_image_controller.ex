defmodule NewtonWeb.OgImageController do
  @moduledoc """
  Renders a post's Open Graph card on demand. The card is generated from the
  live post each request (never stale) and cached at the edge/browser via
  HTTP headers, since crawlers refetch rarely.
  """
  use NewtonWeb, :controller

  alias Newton.Blog
  alias Newton.SocialCard

  @cache_control "public, max-age=3600"

  def show(conn, %{"slug" => slug}) do
    post = Blog.get_published_post!(slug)

    case SocialCard.post_card(%{
           title: post.title,
           excerpt: post.excerpt,
           published_on: post.published_at && DateTime.to_date(post.published_at),
           reading_time: post.reading_time || 1
         }) do
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
