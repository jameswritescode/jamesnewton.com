defmodule NewtonWeb.PageController do
  use NewtonWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: nil, feed: Newton.Feed.recent(10))
  end

  def resume(conn, _params) do
    render(conn, :resume, page_title: "Resume")
  end
end
