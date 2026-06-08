defmodule NewtonWeb.PageControllerTest do
  use NewtonWeb.ConnCase

  test "GET /resume renders the résumé", %{conn: conn} do
    conn = get(conn, ~p"/resume")
    html = html_response(conn, 200)
    assert html =~ "Mark OS"
    assert html =~ "What I'm doing"
  end

  test "GET / shows intro, nav, and a merged feed", %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{slug: "three-ways-to-retry", title: "Three Ways to Retry", body_markdown: "Retry logic.", published_at: ~U[2026-04-17 00:00:00Z]})
    {:ok, _} = Newton.Reading.create_entry(%{title: "Working in Public", author: "Nadia Eghbal", status: :listened, finished_at: ~D[2026-04-13]})

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Hello, I'm James Newton."
    assert html =~ "Three Ways to Retry"
    assert html =~ "Listened to"
    assert html =~ "<cite>Working in Public</cite>"
  end
end
