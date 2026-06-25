defmodule NewtonWeb.LinksController do
  use NewtonWeb, :controller
  alias Newton.Links

  def index(conn, _params) do
    links = Links.all()
    render(conn, :index, page_title: "Links", links: links, first_link: List.first(links))
  end
end
