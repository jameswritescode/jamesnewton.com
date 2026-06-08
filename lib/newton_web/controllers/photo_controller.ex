defmodule NewtonWeb.PhotoController do
  use NewtonWeb, :controller
  alias Newton.Gallery

  def index(conn, _params) do
    render(conn, :index, page_title: "Photos", groups: Gallery.list_groups())
  end
end
