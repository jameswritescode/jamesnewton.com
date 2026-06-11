defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog

  def index(conn, _params) do
    render(conn, :index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug}) do
    post = fetch_post(conn.assigns.current_scope, slug)
    render(conn, :show, page_title: post.title, post: post)
  end

  # A signed-in admin previews any post (drafts included); everyone else (no
  # scope, or a scope without a user) sees only published posts (404 otherwise).
  defp fetch_post(%{user: %{}}, slug), do: Blog.get_post_by_slug!(slug)
  defp fetch_post(_scope, slug), do: Blog.get_published_post!(slug)
end
