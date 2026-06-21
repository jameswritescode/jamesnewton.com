defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog
  alias Newton.Blog.Post

  def index(conn, _params) do
    render(conn, :index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug} = params) do
    case fetch_post(conn.assigns.current_scope, slug, params["p"]) do
      {:preview, post} ->
        conn
        |> assign(:page_robots, "noindex")
        |> render(:show, page_title: post.title, post: post, preview: true)

      post ->
        render(conn, :show, page_title: post.title, post: post, preview: false)
    end
  end

  # A signed-in admin previews any post (drafts included); everyone else sees only
  # published posts, plus the single draft unlocked by a matching ?p token.
  defp fetch_post(%{user: %{}}, slug, _token), do: Blog.get_post_by_slug!(slug)

  defp fetch_post(_scope, slug, token) when is_binary(token) do
    case Blog.get_post_by_preview_token(slug, token) do
      %Post{} = post -> {:preview, post}
      nil -> Blog.get_published_post!(slug)
    end
  end

  defp fetch_post(_scope, slug, _token), do: Blog.get_published_post!(slug)
end
