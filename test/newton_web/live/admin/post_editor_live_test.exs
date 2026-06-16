defmodule NewtonWeb.Admin.PostEditorLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp open_draft(conn, attrs \\ %{}) do
    {:ok, post} =
      Newton.Blog.create_post(
        Enum.into(attrs, %{title: "Untitled post", slug: "untitled-post", body_markdown: ""})
      )

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    {view, post}
  end

  test "Escape closes the publish drawer", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view |> element("button", "Settings") |> render_click()
    assert has_element?(view, "#publish-drawer")

    view |> element("#publish-drawer") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#publish-drawer")
  end

  test "the publish drawer closes on click-away", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view |> element("button", "Settings") |> render_click()
    assert has_element?(view, "#publish-drawer[phx-click-away]")

    render_click(view, "close_drawer", %{})
    refute has_element?(view, "#publish-drawer")
  end

  test "editing a draft persists on submit", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view
    |> form("#post-form",
      post: %{title: "Hello Admin", slug: "hello-admin", body_markdown: "Body text."}
    )
    |> render_submit()

    post = Newton.Blog.get_post_by_slug!("hello-admin")
    assert post.body_html =~ "Body text."
    assert Newton.Blog.publish_status(post.published_at) == :draft
  end

  test "the slug follows the title", %{conn: conn} do
    {view, _post} = open_draft(conn)

    html =
      view
      |> form("#post-form", post: %{title: "My First Post!", slug: "untitled-post"})
      |> render_change()

    assert html =~ ~s(value="my-first-post")
  end

  test "slug keeps following the full title across keystrokes", %{conn: conn} do
    {view, _post} = open_draft(conn)

    # First keystroke: slug derives "h" (the field carries the seeded slug).
    view |> form("#post-form", post: %{title: "h", slug: "untitled-post"}) |> render_change()

    # Later keystroke sends the slug rendered so far ("h"); it must re-derive
    # from the full title rather than freezing at "h".
    html = view |> form("#post-form", post: %{title: "hello", slug: "h"}) |> render_change()
    assert html =~ ~s(value="hello")
  end

  test "a manual slug edit stops the slug from following the title", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view |> form("#post-form", post: %{title: "hello", slug: "untitled-post"}) |> render_change()
    # User types a custom slug (differs from the auto value).
    view |> form("#post-form", post: %{title: "hello", slug: "custom"}) |> render_change()
    # Changing the title no longer touches the slug.
    html =
      view |> form("#post-form", post: %{title: "hello world", slug: "custom"}) |> render_change()

    assert html =~ ~s(value="custom")
  end

  test "excerpt follows the body until the author edits it", %{conn: conn} do
    {view, _post} = open_draft(conn)

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
    {view, _post} = open_draft(conn)

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
    {view, _post} = open_draft(conn)

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish now") |> render_click()

    view
    |> form("#post-form", post: %{title: "Pub", slug: "pub-now", body_markdown: "body"})
    |> render_submit()

    status = Newton.Blog.publish_status(Newton.Blog.get_post_by_slug!("pub-now").published_at)
    assert status == :published
  end

  test "publishing an existing draft persists immediately, without a separate save", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Draft", slug: "draft-pub", body_markdown: "b"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish now") |> render_click()

    status = Newton.Blog.publish_status(Newton.Blog.get_post!(post.id).published_at)
    assert status == :published
  end

  test "moving an existing published post to draft persists immediately", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "live-unpub",
        body_markdown: "b",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Move to draft") |> render_click()

    assert is_nil(Newton.Blog.get_post!(post.id).published_at)
  end

  test "a brand-new post creates no row until there is content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{"post" => %{"title" => "", "body_markdown" => ""}})
    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)
    assert Newton.Blog.list_posts() == []
  end

  test "typing content into a new post creates it and moves to its edit URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "Fresh Post", "slug" => "", "body_markdown" => "Hello body"}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    post = Newton.Blog.get_post_by_slug!("fresh-post")
    assert post.body_html =~ "Hello body"
    assert_patch(view, ~p"/admin/posts/#{post.id}/edit")
  end

  test "a body-only new post is created with a default title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "", "slug" => "", "body_markdown" => "Just a body"}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    [post] = Newton.Blog.list_posts()
    assert post.title == "Untitled post"
    assert post.body_html =~ "Just a body"
  end

  test "setting a past publish date backdates the post", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "backdate",
        body_markdown: "b",
        published_at: ~U[2026-06-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    view |> element("#publish-date-form") |> render_change(%{"date" => "2020-03-15"})

    updated = Newton.Blog.get_post!(post.id)
    assert DateTime.to_date(updated.published_at) == ~D[2020-03-15]
    assert Newton.Blog.publish_status(updated.published_at) == :published
  end

  test "setting a future publish date schedules the post", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "sched",
        body_markdown: "b",
        published_at: ~U[2026-06-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    view |> element("#publish-date-form") |> render_change(%{"date" => "2999-01-01"})

    updated = Newton.Blog.get_post!(post.id)
    assert Newton.Blog.publish_status(updated.published_at) == :scheduled
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
    view |> element("button", "Settings") |> render_click()

    refute has_element?(view, "#publish-drawer button", "Publish now")
    assert has_element?(view, "#publish-drawer button", "Move to draft")
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
    view |> element("button", "Settings") |> render_click()

    view
    |> element("#publish-drawer button", "Delete post")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/posts")

    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(post.id) end
  end

  test "editing a draft auto-saves without a manual save", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "Draft", slug: "auto-draft", body_markdown: "old"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Draft", slug: "auto-draft", body_markdown: "new body"})
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).body_html =~ "new body"
  end

  test "a published post is not auto-saved", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "live-auto",
        body_markdown: "original",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live", slug: "live-auto", body_markdown: "changed"})
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    refute Newton.Blog.get_post!(post.id).body_html =~ "changed"
  end

  test "the editor shows unsaved then saved state for a draft", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "state-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    html = view |> form("#post-form", post: %{body_markdown: "b"}) |> render_change()
    assert html =~ "Unsaved changes"

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)
    refute render(view) =~ "Unsaved changes"
  end

  test "blurring a field flushes the pending auto-save", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "blur-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view |> form("#post-form", post: %{body_markdown: "blurred body"}) |> render_change()
    view |> element("#post_title") |> render_blur()
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).body_html =~ "blurred body"
  end
end
