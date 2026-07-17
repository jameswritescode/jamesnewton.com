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

  test "the settings drawer renders a social card preview", %{conn: conn} do
    {view, _post} = open_draft(conn, %{title: "Card In Editor"})

    refute has_element?(view, "#og-card-preview")

    view |> element("button", "Settings") |> render_click()

    assert has_element?(view, "#og-card-preview[src^='data:image/png;base64,']")
  end

  @png_1x1 <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
             8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0,
             0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  test "dropping an image uploads it and pushes insert_image with a /media URL", %{conn: conn} do
    {view, _post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "shot.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "shot.png")
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end

  test "an upload lands on the post's image ledger", %{conn: conn} do
    {view, post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "shot.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "shot.png")

    assert [attached] = Newton.Blog.list_images(post)
    assert attached.original_filename == "shot.png"
    assert_push_event(view, "insert_image", %{url: url, name: "shot.png", token: nil})
    assert url == "/media/" <> attached.key
  end

  test "a token-prefixed upload is split back into token and original name", %{conn: conn} do
    {view, post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "a1b2c3--shot.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "a1b2c3--shot.png")

    assert [%{original_filename: "shot.png"}] = Newton.Blog.list_images(post)
    assert_push_event(view, "insert_image", %{name: "shot.png", token: "a1b2c3"})
  end

  test "client-rejected files surface as a flash", %{conn: conn} do
    {view, _post} = open_draft(conn)

    render_hook(view, "upload_rejected", %{
      "rejected" => [
        %{"name" => "big.png", "reason" => "size"},
        %{"name" => "vector.svg", "reason" => "type"}
      ]
    })

    html = render(view)
    assert html =~ "big.png"
    assert html =~ "vector.svg"
  end

  test "the hook element publishes the server's upload limits", %{conn: conn} do
    {view, _post} = open_draft(conn)

    assert has_element?(
             view,
             "[id^='markdown-editor'][data-upload-accept][data-upload-max-entries][data-upload-max-file-size]"
           )
  end

  defp editor_key(view) do
    [_, key] = Regex.run(~r/id="markdown-editor-([\w-]+)"/, render(view))
    key
  end

  test "patching to a different post rebuilds the editor region", %{conn: conn} do
    {:ok, a} = Newton.Blog.create_post(%{title: "A", slug: "key-a", body_markdown: "aaa"})
    {:ok, b} = Newton.Blog.create_post(%{title: "B", slug: "key-b", body_markdown: "bbb"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{a.id}/edit")
    key_a = editor_key(view)

    render_patch(view, ~p"/admin/posts/#{b.id}/edit")
    assert editor_key(view) != key_a
  end

  test "patching back to /new after a draft was created rebuilds the editor region", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")
    key_new = editor_key(view)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "keyed.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "keyed.png")
    assert_patch(view)
    assert editor_key(view) == key_new

    render_patch(view, ~p"/admin/posts/new")
    assert editor_key(view) != key_new
  end

  test "typing (validate) between drop and upload completion doesn't lose the upload", %{
    conn: conn
  } do
    {view, post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "race.png", content: @png_1x1, type: "image/png"}
      ])

    view
    |> form("#post-form",
      post: %{title: "Untitled post", slug: "untitled-post", body_markdown: "start more"}
    )
    |> render_change()

    render_upload(image, "race.png")

    assert [%{original_filename: "race.png"}] = Newton.Blog.list_images(post)
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end

  test "an autosave firing mid-upload doesn't lose the upload", %{conn: conn} do
    {view, post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "auto.png", content: @png_1x1, type: "image/png"}
      ])

    view
    |> form("#post-form",
      post: %{title: "Untitled post", slug: "untitled-post", body_markdown: "start more"}
    )
    |> render_change()

    send(view.pid, :autosave)
    _ = render(view)

    render_upload(image, "auto.png")

    assert [%{original_filename: "auto.png"}] = Newton.Blog.list_images(post)
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end

  test "the hook's post-insert flush persists the body before any refresh", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "flush.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "flush.png")
    assert_patch(view)

    assert [post] = Newton.Blog.list_posts(:drafts)
    assert [attached] = Newton.Blog.list_images(post)

    render_change(view, "validate", %{
      "post" => %{
        "title" => "",
        "_unused_title" => "",
        "slug" => "",
        "_unused_slug" => "",
        "body_markdown" => "![](/media/#{attached.key})"
      }
    })

    render_hook(view, "autosave_now", %{})
    _ = render(view)

    reloaded = Newton.Blog.get_post!(post.id)
    assert reloaded.body_markdown =~ attached.key
    assert Newton.Blog.image_referenced?(reloaded, attached)
    assert reloaded.title == post.title
    assert reloaded.slug == post.slug

    assert has_element?(view, ~s(#post-form input[name="post[title]"][value="#{post.title}"]))
    assert has_element?(view, ~s(#post-form input[name="post[slug]"][value="#{post.slug}"]))
  end

  test "a deliberately cleared title is not resurrected into the form by a flush", %{conn: conn} do
    {view, post} = open_draft(conn, %{title: "Keep Me", slug: "keep-me", body_markdown: "old"})

    render_change(view, "validate", %{
      "post" => %{"title" => "", "slug" => "keep-me", "body_markdown" => "old and new"}
    })

    render_hook(view, "autosave_now", %{})
    _ = render(view)

    reloaded = Newton.Blog.get_post!(post.id)
    assert reloaded.body_markdown == "old and new"
    assert reloaded.title == "Keep Me"

    refute has_element?(view, ~s(#post-form input[name="post[title]"][value="Keep Me"]))
  end

  test "a flush carrying the body persists it without a preceding validate", %{conn: conn} do
    {view, post} = open_draft(conn, %{title: "Payload", slug: "payload", body_markdown: "old"})

    render_hook(view, "autosave_now", %{"body_markdown" => "payload body wins"})
    _ = render(view)

    assert Newton.Blog.get_post!(post.id).body_markdown == "payload body wins"
  end

  test "autosave persists a changed, non-blank title", %{conn: conn} do
    {view, post} = open_draft(conn, %{title: "Before", slug: "before-slug"})

    render_change(view, "validate", %{
      "post" => %{"title" => "After", "slug" => "before-slug", "body_markdown" => "body"}
    })

    render_hook(view, "autosave_now", %{})
    _ = render(view)

    assert Newton.Blog.get_post!(post.id).title == "After"
  end

  test "the first upload on a brand-new post creates the draft and attaches to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "first.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "first.png")
    assert_patch(view)

    assert [post] = Newton.Blog.list_posts(:drafts)
    assert [%{original_filename: "first.png"}] = Newton.Blog.list_images(post)
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
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

  defp excerpt_value(html) do
    case Regex.run(~r/<textarea[^>]*name="post\[excerpt\]"[^>]*>([^<]*)<\/textarea>/, html) do
      [_, content] -> content
      _ -> :no_excerpt_textarea
    end
  end

  test "slug follows the title while the slug field stays untouched", %{conn: conn} do
    {view, _post} = open_draft(conn)

    # Real browser: the user types only in the title. LiveView marks the slug
    # untouched (_unused_slug) and submits a value that lags the derived slug.
    # The slug must keep following the title rather than locking on the stale value.
    render_change(view, "validate", %{
      "post" => %{"title" => "h", "slug" => "untitled-post", "_unused_slug" => ""}
    })

    html =
      render_change(view, "validate", %{
        "post" => %{"title" => "hello world", "slug" => "untitled-post", "_unused_slug" => ""}
      })

    assert html =~ ~s(value="hello-world")
    refute html =~ ~s(value="untitled-post")
  end

  test "excerpt follows the body while the excerpt field stays untouched", %{conn: conn} do
    {view, _post} = open_draft(conn, %{body_markdown: "Seed body paragraph."})
    stale = "Seed body paragraph."

    # Real browser: the user types in the body only. The excerpt is untouched
    # (_unused_excerpt) and submits its stale rendered value; it must keep
    # following the body rather than locking on the stale value.
    render_change(view, "validate", %{
      "post" => %{"body_markdown" => "Second body version.", "excerpt" => stale, "_unused_excerpt" => ""}
    })

    html =
      render_change(view, "validate", %{
        "post" => %{
          "body_markdown" => "Third body version now.",
          "excerpt" => stale,
          "_unused_excerpt" => ""
        }
      })

    assert excerpt_value(html) == "Third body version now."
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

    assert has_element?(view, "[id^='markdown-editor'][phx-hook='MarkdownEditor']")
    assert has_element?(view, "textarea[name='post[body_markdown]']")
    assert render(view) =~ "# Seeded body"
  end

  test "delete removes the post and redirects to the list", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "Kill", slug: "kill", body_markdown: "b"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    view
    |> element("#publish-drawer button", "Delete")
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

  test "a draft autosave shows the Save button as Saving and disabled, then back to Save", %{
    conn: conn
  } do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "state-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view |> form("#post-form", post: %{body_markdown: "b"}) |> render_change()
    assert has_element?(view, "#post-form button[type='submit'][disabled]", "Saving")

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    refute has_element?(view, "#post-form button[type='submit'][disabled]")
    assert has_element?(view, "#post-form button[type='submit']", "Save")
  end

  test "a published post's Save button stays enabled even when dirty", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "btn-live",
        body_markdown: "b",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live Edited", slug: "btn-live", body_markdown: "b"})
    |> render_change()

    refute has_element?(view, "#post-form button[type='submit'][disabled]")
    assert has_element?(view, "#post-form button[type='submit']", "Save")
  end

  test "blurring a field flushes the pending auto-save", %{conn: conn} do
    {:ok, post} = Newton.Blog.create_post(%{title: "D", slug: "blur-draft", body_markdown: "a"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view |> form("#post-form", post: %{body_markdown: "blurred body"}) |> render_change()
    view |> element("#post_title") |> render_blur()
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).body_html =~ "blurred body"
  end

  test "editing a published post flags unsaved changes and the leave guard", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-live",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")

    view
    |> form("#post-form",
      post: %{title: "Live Edited", slug: "guard-live", body_markdown: "body"}
    )
    |> render_change()

    assert render(view) =~ "Unsaved changes"
    assert has_element?(view, "#unsaved-guard[data-unsaved='true']")
  end

  test "saving a published post clears the unsaved flag", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-save",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form",
      post: %{title: "Live Edited", slug: "guard-save", body_markdown: "body"}
    )
    |> render_change()

    view
    |> form("#post-form",
      post: %{title: "Live Edited", slug: "guard-save", body_markdown: "body"}
    )
    |> render_submit()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
    refute render(view) =~ "Unsaved changes"

    # The saved values are the new baseline: re-submitting them is not dirty.
    view
    |> form("#post-form",
      post: %{title: "Live Edited", slug: "guard-save", body_markdown: "body"}
    )
    |> render_change()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
  end

  test "re-typing the saved values leaves a published post not dirty", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-same",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live", slug: "guard-same", body_markdown: "body"})
    |> render_change()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
  end

  test "a draft never sets the unsaved leave guard", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view
    |> form("#post-form", post: %{title: "Typing a draft", slug: "typing-a-draft"})
    |> render_change()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
  end

  test "enabling and disabling the preview link on a saved draft", %{conn: conn} do
    {view, post} = open_draft(conn)
    view |> element("button", "Settings") |> render_click()

    refute render(view) =~ "?p="

    view |> element("#publish-drawer button", "Enable preview link") |> render_click()

    updated = Newton.Blog.get_post!(post.id)
    assert updated.preview_token
    assert render(view) =~ "?p=#{updated.preview_token}"

    view |> element("#publish-drawer button", "Turn off preview link") |> render_click()
    assert is_nil(Newton.Blog.get_post!(post.id).preview_token)
  end

  test "the preview control is hidden once a post is published", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Pub",
        slug: "pub-preview",
        body_markdown: "b",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    refute has_element?(view, "#publish-drawer button", "Enable preview link")
  end

  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "deleting an unreferenced image removes it from disk, ledger, and page", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Img",
        slug: "img-post",
        body_markdown: "No pics anymore."
      })

    {:ok, image} = Newton.Blog.attach_image(post, "stale.png", "stale.png")
    path = stored_file("stale.png")

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#post-image-#{image.id}")

    view |> element("#post-image-#{image.id} button", "Delete") |> render_click()

    refute has_element?(view, "#post-image-#{image.id}")
    refute File.exists?(path)
    assert Newton.Blog.list_images(post) == []
  end

  test "a referenced image shows no delete button and survives a forged delete", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Img",
        slug: "img-post-2",
        body_markdown: "![](/media/live.png)"
      })

    {:ok, image} = Newton.Blog.attach_image(post, "live.png", "live.png")
    stored_file("live.png")

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#post-image-#{image.id}")
    refute has_element?(view, "#post-image-#{image.id} button")

    render_click(view, "delete_image", %{"id" => to_string(image.id)})
    assert [_] = Newton.Blog.list_images(post)
  end

  test "an upload appears in the Images section immediately", %{conn: conn} do
    {view, _post} = open_draft(conn)

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "fresh.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "fresh.png")
    assert has_element?(view, "#post-images")
  end
end
