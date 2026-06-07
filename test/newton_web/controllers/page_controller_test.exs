defmodule NewtonWeb.PageControllerTest do
  use NewtonWeb.ConnCase

  test "GET /resume renders the résumé", %{conn: conn} do
    conn = get(conn, ~p"/resume")
    html = html_response(conn, 200)
    assert html =~ "Mark OS"
    assert html =~ "What I'm doing"
  end
end
