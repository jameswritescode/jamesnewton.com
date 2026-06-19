defmodule NewtonWeb.ErrorHTMLTest do
  use NewtonWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "statuses without a template fall back to the plain status message" do
    assert render_to_string(NewtonWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end

  test "an unknown route renders the styled 404 page", %{conn: conn} do
    conn = get(conn, "/no-such-page")

    assert conn.status == 404
    body = conn.resp_body
    assert body =~ "404"
    assert body =~ "wandered off"
    assert body =~ "Back home"
    # rendered inside the root layout (canvas) with the frown marker
    assert body =~ "rippleCanvas"
    assert body =~ "data-frown"
  end

  test "a missing post renders the styled 404 page", %{conn: conn} do
    # A missing record raises Ecto.NoResultsError, which Phoenix maps to 404 and
    # renders through the same error view.
    assert {404, _headers, body} =
             assert_error_sent(404, fn -> get(conn, "/posts/does-not-exist") end)

    assert body =~ "wandered off"
  end
end
