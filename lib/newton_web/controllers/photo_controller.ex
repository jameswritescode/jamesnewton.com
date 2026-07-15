defmodule NewtonWeb.PhotoController do
  use NewtonWeb, :controller
  alias Newton.Gallery

  def index(conn, _params) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: "Photos",
      description: "Photography from hikes, travel, and other events.",
      path: "/photos"
    })
    |> render(:index, page_title: "Photos", groups: Gallery.list_groups())
  end
end
