defmodule NewtonWeb.ReadingController do
  use NewtonWeb, :controller
  alias Newton.Reading

  def index(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Reading",
      description: "Books read and listened to, with occasional notes.",
      path: "/reading"
    })
    |> render(:index, page_title: "Reading", entries: Reading.list_entries())
  end
end
