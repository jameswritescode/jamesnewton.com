defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog

  def index(conn, _params) do
    render(conn, :index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug}) do
    post = Blog.get_published_post!(slug)
    render(conn, :show, page_title: post.title, post: post)
  end
end
