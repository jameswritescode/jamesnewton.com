defmodule NewtonWeb.ReadingController do
  use NewtonWeb, :controller
  alias Newton.Reading

  def index(conn, _params) do
    render(conn, :index, page_title: "Reading", entries: Reading.list_entries())
  end
end
