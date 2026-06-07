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
end
