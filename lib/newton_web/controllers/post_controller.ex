defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog
  alias Newton.Blog.Post

  def index(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Posts",
      description: "Writing on software and other things.",
      path: "/posts"
    })
    |> render(:index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug} = params) do
    case fetch_post(conn.assigns.current_scope, slug, params["p"]) do
      {:preview, kind, post} ->
        conn
        |> assign(:page_robots, "noindex")
        |> SEO.assign(post)
        |> render(:show, page_title: post.title, post: post, preview: kind)

      post ->
        conn
        |> SEO.assign(post)
        |> assign(
          :standard_document,
          post.published_at && Newton.Standard.document_uri(post.slug)
        )
        |> render(:show, page_title: post.title, post: post, preview: nil)
    end
  end

  # A signed-in admin previews any post (drafts included); everyone else sees only
  # published posts, plus the single draft unlocked by a matching ?p token.
  defp fetch_post(%{user: %{}}, slug, _token) do
    post = Blog.get_post_by_slug!(slug)

    if Post.live?(post.published_at) do
      post
    else
      {:preview, :admin, post}
    end
  end

  defp fetch_post(_scope, slug, token) when is_binary(token) do
    case Blog.get_post_by_preview_token(slug, token) do
      %Post{} = post -> {:preview, :link, post}
      nil -> Blog.get_published_post!(slug)
    end
  end

  defp fetch_post(_scope, slug, _token), do: Blog.get_published_post!(slug)
end
