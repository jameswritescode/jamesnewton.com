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

  test "loads an existing post and updates it", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Original", slug: "original", body_markdown: "old body"})

    {:ok, view, html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert html =~ "Original"

    view
    |> form("#post-form", post: %{title: "Updated", slug: "original", body_markdown: "new body"})
    |> render_submit()
    |> follow_redirect(conn, ~p"/admin/posts")

    updated = Newton.Blog.get_post!(post.id)
    assert updated.title == "Updated"
    assert updated.body_html =~ "new body"
  end

  test "publish-now sets the post to published on save", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> element("button", "Publish now") |> render_click()

    view
    |> form("#post-form", post: %{title: "Pub", slug: "pub-now", body_markdown: "body"})
    |> render_submit()
    |> follow_redirect(conn, ~p"/admin/posts")

    status = Newton.Blog.publish_status(Newton.Blog.get_post_by_slug!("pub-now").published_at)
    assert status == :published
  end

  test "scheduling a future date marks the post as scheduled on save", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    future = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
    view |> element("#schedule-date") |> render_change(%{"value" => future})

    view
    |> form("#post-form", post: %{title: "Sched", slug: "sched", body_markdown: "body"})
    |> render_submit()
    |> follow_redirect(conn, ~p"/admin/posts")

    status = Newton.Blog.publish_status(Newton.Blog.get_post_by_slug!("sched").published_at)
    assert status == :scheduled
  end

  test "delete removes the post and redirects to the list", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "Kill", slug: "kill", body_markdown: "b"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> element("button", "Delete post")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/posts")

    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(post.id) end
  end
end
