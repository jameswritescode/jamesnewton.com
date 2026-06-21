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

  describe "draft visibility" do
    setup do
      {:ok, draft} =
        Blog.create_post(%{
          slug: "secret-draft",
          title: "Secret Draft",
          body_markdown: "Hidden body.",
          published_at: nil
        })

      %{draft: draft}
    end

    test "anonymous visitors get 404 for a draft", %{conn: conn, draft: draft} do
      assert_error_sent 404, fn -> get(conn, ~p"/posts/#{draft.slug}") end
    end

    test "a signed-in admin can preview a draft at its real URL", %{conn: conn, draft: draft} do
      {:ok, user} = Newton.Release.create_admin("preview@example.com", "supersecret123")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/posts/#{draft.slug}")

      assert html_response(conn, 200) =~ "Secret Draft"
    end

    test "a draft is visible with a valid ?p token and carries noindex", %{conn: conn, draft: draft} do
      {:ok, draft} = Blog.enable_preview(draft)

      html = conn |> get(~p"/posts/#{draft.slug}?#{[p: draft.preview_token]}") |> html_response(200)
      assert html =~ "Secret Draft"
      assert html =~ "Draft preview"
      assert html =~ ~s(name="robots")
      assert html =~ "noindex"
    end

    test "a draft 404s with a wrong or missing ?p token", %{conn: conn, draft: draft} do
      {:ok, draft} = Blog.enable_preview(draft)

      assert_error_sent 404, fn -> get(conn, ~p"/posts/#{draft.slug}?#{[p: "nope"]}") end
      assert_error_sent 404, fn -> get(conn, ~p"/posts/#{draft.slug}") end
    end

    test "a published post renders without a token and is not noindex", %{conn: conn} do
      {:ok, _} =
        Blog.create_post(%{
          slug: "live-one",
          title: "Live One",
          body_markdown: "Body.",
          published_at: ~U[2026-01-01 00:00:00Z]
        })

      html = conn |> get(~p"/posts/live-one") |> html_response(200)
      assert html =~ "Live One"
      refute html =~ "noindex"
      refute html =~ "Draft preview"
    end
  end
end
