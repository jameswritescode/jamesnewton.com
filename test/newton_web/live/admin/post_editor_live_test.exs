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

  test "auto-fills the slug from the title while the slug is blank", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "My First Post!", slug: "", body_markdown: "x"})
      |> render_change()

    assert html =~ ~s(value="my-first-post")
  end

  test "shows validation errors on invalid submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "", slug: "", body_markdown: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end
end
