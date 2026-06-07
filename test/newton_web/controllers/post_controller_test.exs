defmodule NewtonWeb.PostControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Blog

  setup do
    {:ok, post} =
      Blog.create_post(%{
        slug: "three-ways-to-retry",
        title: "Three Ways to Retry",
        body_markdown: "Retry logic is one of those small utilities.\n\n## The problem\n\nText.",
        published_at: ~U[2026-04-17 00:00:00Z]
      })

    %{post: post}
  end

  test "GET /posts lists published posts", %{conn: conn} do
    html = conn |> get(~p"/posts") |> html_response(200)
    assert html =~ "Three Ways to Retry"
    assert html =~ ~p"/posts/three-ways-to-retry"
  end

  test "GET /posts/:slug renders the rendered HTML body", %{conn: conn} do
    html = conn |> get(~p"/posts/three-ways-to-retry") |> html_response(200)
    assert html =~ "<h2"
    assert html =~ "The problem"
  end

  test "GET /posts/:slug 404s on unknown slug", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/posts/does-not-exist") end
  end
end
