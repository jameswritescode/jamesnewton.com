defmodule NewtonWeb.LinksController do
  use NewtonWeb, :controller
  alias Newton.Links

  def index(conn, _params) do
    render(conn, :index, page_title: "Links", links: Links.all())
  end
end
