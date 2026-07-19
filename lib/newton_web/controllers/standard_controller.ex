defmodule NewtonWeb.StandardController do
  @moduledoc "Serves the standard.site publication pointer for AppView verification."
  use NewtonWeb, :controller

  def publication(conn, _params) do
    case Newton.Standard.publication_uri() do
      nil ->
        send_resp(conn, 404, "")

      uri ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, uri)
    end
  end
end
