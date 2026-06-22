defmodule NewtonWeb.PageControllerTest do
  use NewtonWeb.ConnCase

  test "GET /blog/:slug redirects permanently to /posts/:slug", %{conn: conn} do
    conn = get(conn, "/blog/three-ways-to-retry")
    assert redirected_to(conn, 301) == "/posts/three-ways-to-retry"
  end

  test "GET /blog redirects permanently to /posts", %{conn: conn} do
    conn = get(conn, "/blog")
    assert redirected_to(conn, 301) == "/posts"
  end

  test "GET /resume renders the résumé", %{conn: conn} do
    conn = get(conn, ~p"/resume")
    html = html_response(conn, 200)
    assert html =~ "Mark OS"
    assert html =~ "What I'm doing"
  end

  test "GET / shows intro, nav, and a merged feed", %{conn: conn} do
    {:ok, _} =
      Newton.Blog.create_post(%{
        slug: "three-ways-to-retry",
        title: "Three Ways to Retry",
        body_markdown: "Retry logic.",
        published_at: ~U[2026-04-17 00:00:00Z]
      })

    {:ok, _} =
      Newton.Reading.create_entry(%{
        title: "Working in Public",
        author: "Nadia Eghbal",
        status: :listened,
        finished_at: ~D[2026-04-13]
      })

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Hello, I'm James Newton."
    assert html =~ "Three Ways to Retry"
    assert html =~ "Listened to"
    assert html =~ "<cite>Working in Public</cite>"
  end

  test "the home page exposes default website OG tags", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(property="og:type" content="website")
    assert html =~ "og-default.png"
  end

  test "the home feed shows at most 5 items", %{conn: conn} do
    for i <- 1..6 do
      {:ok, _} =
        Newton.Blog.create_post(%{
          slug: "p#{i}",
          title: "P#{i}",
          body_markdown: "B.",
          published_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :day)
        })
    end

    html = conn |> get(~p"/") |> html_response(200)
    feed_items = html |> String.split("feed-item-date") |> length() |> Kernel.-(1)
    assert feed_items == 5
  end

  test "the page head references the theme-aware favicon", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(rel="icon")
    assert html =~ "/favicon.svg"
    assert html =~ ~s(rel="apple-touch-icon")
  end
end
