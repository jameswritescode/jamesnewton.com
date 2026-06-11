defmodule NewtonWeb.Admin.PostEditorLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "Escape closes the publish drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> element("button", "Settings") |> render_click()
    assert has_element?(view, "#publish-drawer.translate-x-0")

    view |> element("#publish-drawer") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#publish-drawer.translate-x-0")
  end

  test "creates a post and stays in the editor on its edit URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view
    |> form("#post-form",
      post: %{title: "Hello Admin", slug: "hello-admin", body_markdown: "Body text."}
    )
    |> render_submit()

    post = Newton.Blog.get_post_by_slug!("hello-admin")
    assert_patch(view, ~p"/admin/posts/#{post.id}/edit")
    assert post.body_html =~ "Body text."
  end

  test "auto-fills the slug from the title while the slug is blank", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form", post: %{title: "My First Post!", slug: "", body_markdown: "x"})
      |> render_change()

    assert html =~ ~s(value="my-first-post")
  end

  test "slug keeps following the full title across keystrokes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    # First keystroke: slug becomes "h".
    view |> form("#post-form", post: %{title: "h", slug: ""}) |> render_change()

    # Later keystroke sends the slug rendered so far ("h"); it must re-derive
    # from the full title rather than freezing at "h".
    html = view |> form("#post-form", post: %{title: "hello", slug: "h"}) |> render_change()
    assert html =~ ~s(value="hello")
  end

  test "a manual slug edit stops the slug from following the title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    view |> form("#post-form", post: %{title: "hello", slug: ""}) |> render_change()
    # User types a custom slug (differs from the auto value).
    view |> form("#post-form", post: %{title: "hello", slug: "custom"}) |> render_change()
    # Changing the title no longer touches the slug.
    html =
      view |> form("#post-form", post: %{title: "hello world", slug: "custom"}) |> render_change()

    assert html =~ ~s(value="custom")
  end

  test "excerpt follows the body until the author edits it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    html =
      view
      |> form("#post-form",
        post: %{title: "T", body_markdown: "The first paragraph of the body."}
      )
      |> render_change()

    assert html =~ "The first paragraph of the body."

    # Editing the excerpt locks it; further body changes leave it alone.
    view
    |> form("#post-form",
      post: %{body_markdown: "Different body now.", excerpt: "My custom excerpt"}
    )
    |> render_change()

    html =
      view
      |> form("#post-form",
        post: %{body_markdown: "Changed again.", excerpt: "My custom excerpt"}
      )
      |> render_change()

    assert html =~ "My custom excerpt"
    refute html =~ "Changed again."
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

    status = Newton.Blog.publish_status(Newton.Blog.get_post_by_slug!("pub-now").published_at)
    assert status == :published
  end

  test "an already-published post hides Publish now and offers Move to draft", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "live",
        body_markdown: "b",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    refute has_element?(view, "button", "Publish now")
    assert has_element?(view, "button", "Move to draft")
  end

  test "the editor renders a markdown editor seeded from the post body", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "MD", slug: "md", body_markdown: "# Seeded body"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    assert has_element?(view, "#markdown-editor[phx-hook='MarkdownEditor']")
    assert has_element?(view, "textarea#post_body_markdown")
    assert render(view) =~ "# Seeded body"
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
