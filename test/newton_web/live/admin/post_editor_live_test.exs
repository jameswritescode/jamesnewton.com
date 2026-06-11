defmodule NewtonWeb.Admin.PostEditorLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "creates a post and redirects to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    {:ok, _index, html} =
      view
      |> form("#post-form",
        post: %{title: "Hello Admin", slug: "hello-admin", body_markdown: "Body text."}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/posts")

    assert html =~ "Hello Admin"
    assert Newton.Blog.get_post_by_slug!("hello-admin").body_html =~ "Body text."
  end
end
