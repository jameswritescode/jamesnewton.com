defmodule NewtonWeb.PageController do
  use NewtonWeb, :controller

  def home(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "James Newton",
      description: "Software & Photography",
      path: "/"
    })
    |> render(:home, page_title: nil, feed: Newton.Feed.recent(5))
  end

  def resume(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Resume",
      description: "Experience and work history.",
      path: "/resume"
    })
    |> render(:resume, page_title: "Resume")
  end

  # The blog used to live at /blog; 301 the old URLs to /posts for SEO.
  def blog_redirect(conn, %{"slug" => slug}) do
    conn |> put_status(:moved_permanently) |> redirect(to: ~p"/posts/#{slug}")
  end

  def blog_redirect(conn, _params) do
    conn |> put_status(:moved_permanently) |> redirect(to: ~p"/posts")
  end
end
