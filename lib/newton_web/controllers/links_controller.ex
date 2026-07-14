defmodule NewtonWeb.LinksController do
  use NewtonWeb, :controller
  alias Newton.Links

  def index(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Links",
      description: "Where to find me elsewhere on the internet.",
      path: "/links"
    })
    |> render(:index, page_title: "Links", links: Links.all())
  end
end
