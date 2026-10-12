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

  test "the hook element publishes limits matching the server's upload config", %{conn: conn} do
    {view, _post} = open_draft(conn)
    html = render(view)

    assert [_, accept] = Regex.run(~r/data-upload-accept="([^"]*)"/, html)
    assert [_, max_entries] = Regex.run(~r/data-upload-max-entries="([^"]*)"/, html)
    assert [_, max_file_size] = Regex.run(~r/data-upload-max-file-size="([^"]*)"/, html)

    assert accept == ".jpg,.jpeg,.png,.webp,.gif"
    assert max_entries == "10"
    assert max_file_size == "50000000"
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

  test "the first upload keeps a title typed on a brand-new post", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{
        "title" => "Kept Title",
        "slug" => "",
        "_unused_slug" => "",
        "body_markdown" => ""
      }
    })

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "kept.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "kept.png")
    assert_patch(view)

    assert [post] = Newton.Blog.list_posts(:drafts)
    assert post.title == "Kept Title"
    assert post.slug == "kept-title"
    assert has_element?(view, "#post-form input[name='post[title]'][value='Kept Title']")
  end

  test "the first upload on an untitled post creates an Untitled draft", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    image =
      file_input(view, "#post-form", :inline_images, [
        %{name: "untitled.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "untitled.png")
    assert_patch(view)

    assert [%{title: "Untitled" <> _}] = Newton.Blog.list_posts(:drafts)
  end

  describe "the first image on an empty new post" do
    test "shows the created draft's identity in the same reply", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      html = upload_inline_image(view, "identity.png")

      [post] = Newton.Blog.list_posts(:drafts)
      assert input_value(html, "post[title]") == "Untitled post"
      assert input_value(html, "post[slug]") == post.slug
    end

    test "keeps the identity when a stale blank change follows", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      upload_inline_image(view, "stale-identity.png")
      assert_patch(view)

      html =
        render_change(view, "validate", %{
          "post" => %{
            "title" => "",
            "_unused_title" => "",
            "slug" => "",
            "_unused_slug" => "",
            "excerpt" => "",
            "_unused_excerpt" => "",
            "body_markdown" => "![](/media/x.png)"
          }
        })

      assert input_value(html, "post[title]") == "Untitled post"
      assert input_value(html, "post[slug]") =~ ~r/\Auntitled/
    end
  end

  defp input_value(html, name) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[name='#{name}']")
    |> LazyHTML.attribute("value")
    |> List.first()
  end

  describe "a blank slug on a new post" do
    test "is derived from the title when the first image creates the draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      render_change(view, "validate", %{
        "post" => %{"title" => "Cleared Slug", "slug" => "", "_unused_slug" => ""}
      })

      render_change(view, "validate", %{
        "post" => %{"title" => "Cleared Slug", "slug" => "", "body_markdown" => ""}
      })

      upload_inline_image(view, "cleared.png")
      assert_patch(view)

      assert [post] = Newton.Blog.list_posts(:drafts)
      assert post.slug == "cleared-slug"
      assert [%{original_filename: "cleared.png"}] = Newton.Blog.list_images(post)
    end

    test "is derived from the title on manual save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      view
      |> form("#post-form", post: %{title: "Saved Blank", slug: "", body_markdown: ""})
      |> render_submit()

      assert [%{slug: "saved-blank"}] = Newton.Blog.list_posts(:drafts)
    end

    test "keeps following the title when a stale blank slug arrives after the first image",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

      render_change(view, "validate", %{
        "post" => %{"title" => "Cleared Slug", "slug" => "", "_unused_slug" => ""}
      })

      upload_inline_image(view, "stale.png")
      assert_patch(view)

      render_change(view, "validate", %{
        "post" => %{"title" => "Cleared Slug", "slug" => "", "body_markdown" => "![](x)"}
      })

      assert has_element?(view, "#post-form input[name='post[slug]'][value='cleared-slug']")

      render_change(view, "validate", %{
        "post" => %{"title" => "Renamed", "slug" => "cleared-slug", "body_markdown" => "![](x)"}
      })

      assert has_element?(view, "#post-form input[name='post[slug]'][value='renamed']")
    end

    test "refills from the title when cleared on a draft", %{conn: conn} do
      {view, _post} = open_draft(conn, %{title: "Custom Draft", slug: "my-own-slug"})

      render_change(view, "validate", %{"post" => %{"title" => "Custom Draft", "slug" => ""}})

      assert has_element?(view, "#post-form input[name='post[slug]'][value='custom-draft']")

      render_change(view, "validate", %{
        "post" => %{"title" => "Retitled Draft", "slug" => "custom-draft"}
      })

      assert has_element?(view, "#post-form input[name='post[slug]'][value='retitled-draft']")
    end

    test "is not derived from the title once published", %{conn: conn} do
      {view, _post} =
        open_draft(conn, %{
          title: "Live Title",
          slug: "live-slug",
          published_at: ~U[2026-01-01 00:00:00Z]
        })

      render_change(view, "validate", %{"post" => %{"title" => "Live Title", "slug" => ""}})

      refute has_element?(view, "#post-form input[name='post[slug]'][value='live-title']")
    end
  end

  test "an Untitled draft from a first image takes its slug from the title typed later",
       %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{title: "Older", slug: "untitled-post"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    upload_inline_image(view, "placeholder.png")
    assert_patch(view)

    post = Newton.Blog.get_post_by_slug!("untitled-post-2")

    render_change(view, "validate", %{
      "post" => %{"title" => "Real Title", "slug" => post.slug, "_unused_slug" => ""}
    })

    assert has_element?(view, "#post-form input[name='post[slug]'][value='real-title']")

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).slug == "real-title"
  end

  test "an Untitled draft keeps its generated slug until a real title is typed",
       %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{title: "Older", slug: "untitled-post"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    upload_inline_image(view, "placeholder.png")
    assert_patch(view)

    post = Newton.Blog.get_post_by_slug!("untitled-post-2")

    render_change(view, "validate", %{
      "post" => %{"title" => "Untitled post", "slug" => post.slug, "body_markdown" => "Words."}
    })

    assert has_element?(view, "#post-form input[name='post[slug]'][value='untitled-post-2']")

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Blog.get_post!(post.id).slug == "untitled-post-2"
  end

  test "a slug collision on the first image shows the error and creates nothing",
       %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{title: "Elsewhere", slug: "taken"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "Taken", "slug" => "", "_unused_slug" => "", "body_markdown" => ""}
    })

    upload_inline_image(view, "collide.png")

    assert [%{title: "Elsewhere"}] = Newton.Blog.list_posts(:drafts)
    assert has_element?(view, slug_error_selector(), "has already been taken")
    assert has_element?(view, "#post-form input[name='post[title]'][value='Taken']")
  end

  test "a slug collision on a new post's autosave shows the error", %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{title: "Elsewhere", slug: "taken"})
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "Taken", "slug" => "", "_unused_slug" => "", "body_markdown" => ""}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert [%{title: "Elsewhere"}] = Newton.Blog.list_posts(:drafts)
    assert has_element?(view, slug_error_selector(), "has already been taken")
  end

  defp slug_error_selector, do: "#post-form .fieldset:has(input[name='post[slug]']) p"

  defp upload_inline_image(view, name) do
    view
    |> file_input("#post-form", :inline_images, [
      %{name: name, content: @png_1x1, type: "image/png"}
    ])
    |> render_upload(name)
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
      "post" => %{
        "body_markdown" => "Second body version.",
        "excerpt" => stale,
        "_unused_excerpt" => ""
      }
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

  describe "typing faster than the server replies" do
    @harbour "The harbour was quiet this morning."

    test "a stale excerpt on a body keystroke keeps following the body", %{conn: conn} do
      {view, _post} = open_draft(conn, %{body_markdown: @harbour, excerpt: @harbour})

      render_change(view, "validate", %{
        "_target" => ["post", "excerpt"],
        "post" => %{"body_markdown" => @harbour, "excerpt" => ""}
      })

      render_change(view, "validate", %{
        "_target" => ["post", "body_markdown"],
        "post" => %{"body_markdown" => @harbour <> " B", "excerpt" => @harbour}
      })

      html =
        render_change(view, "validate", %{
          "_target" => ["post", "body_markdown"],
          "post" => %{"body_markdown" => @harbour <> " Boats", "excerpt" => @harbour}
        })

      assert excerpt_value(html) == @harbour <> " Boats"
    end

    test "a stale slug on a title keystroke keeps following the title", %{conn: conn} do
      {view, _post} = open_draft(conn)

      render_change(view, "validate", %{
        "_target" => ["post", "title"],
        "post" => %{"title" => "A", "slug" => "untitled-post"}
      })

      render_change(view, "validate", %{
        "_target" => ["post", "title"],
        "post" => %{"title" => "Ab", "slug" => "a"}
      })

      html =
        render_change(view, "validate", %{
          "_target" => ["post", "title"],
          "post" => %{"title" => "Abc", "slug" => "a"}
        })

      assert input_value(html, "post[slug]") == "abc"
    end

    test "an edit to the excerpt itself still locks it", %{conn: conn} do
      {view, _post} = open_draft(conn, %{body_markdown: @harbour, excerpt: @harbour})

      render_change(view, "validate", %{
        "_target" => ["post", "excerpt"],
        "post" => %{"body_markdown" => @harbour, "excerpt" => "My custom excerpt"}
      })

      html =
        render_change(view, "validate", %{
          "_target" => ["post", "body_markdown"],
          "post" => %{"body_markdown" => "A newer body.", "excerpt" => "My custom excerpt"}
        })

      assert excerpt_value(html) == "My custom excerpt"
    end

    test "an edit to the slug itself still locks it", %{conn: conn} do
      {view, _post} = open_draft(conn)

      render_change(view, "validate", %{
        "_target" => ["post", "slug"],
        "post" => %{"title" => "Untitled post", "slug" => "custom"}
      })

      html =
        render_change(view, "validate", %{
          "_target" => ["post", "title"],
          "post" => %{"title" => "A Real Title", "slug" => "custom"}
        })

      assert input_value(html, "post[slug]") == "custom"
    end
  end

  describe "a cleared excerpt" do
    test "re-derives from the body and keeps following it", %{conn: conn} do
      {view, _post} = open_draft(conn, %{body_markdown: "Seed body paragraph."})

      render_change(view, "validate", %{
        "post" => %{"body_markdown" => "Seed body paragraph.", "excerpt" => "Custom words"}
      })

      html =
        render_change(view, "validate", %{
          "post" => %{"body_markdown" => "Seed body paragraph.", "excerpt" => ""}
        })

      assert excerpt_value(html) == "Seed body paragraph."

      html =
        render_change(view, "validate", %{
          "post" => %{
            "body_markdown" => "A newer body.",
            "excerpt" => "Seed body paragraph.",
            "_unused_excerpt" => ""
          }
        })

      assert excerpt_value(html) == "A newer body."
    end

    test "locks again once the author types a custom value", %{conn: conn} do
      {view, _post} = open_draft(conn, %{body_markdown: "Seed body paragraph."})

      render_change(view, "validate", %{
        "post" => %{"body_markdown" => "Seed body paragraph.", "excerpt" => ""}
      })

      render_change(view, "validate", %{
        "post" => %{"body_markdown" => "Seed body paragraph.", "excerpt" => "Mine now"}
      })

      html =
        render_change(view, "validate", %{
          "post" => %{
            "body_markdown" => "A newer body.",
            "excerpt" => "Mine now",
            "_unused_excerpt" => ""
          }
        })

      assert excerpt_value(html) == "Mine now"
    end
  end

  describe "refilling a cleared derived field in the browser" do
    test "pushes the body's excerpt when the excerpt is cleared", %{conn: conn} do
      {view, _post} =
        open_draft(conn, %{body_markdown: "Seed body paragraph.", excerpt: "Custom words"})

      render_change(view, "validate", %{
        "post" => %{
          "title" => "Untitled post",
          "_unused_title" => "",
          "slug" => "untitled-post",
          "_unused_slug" => "",
          "body_markdown" => "Seed body paragraph.",
          "_unused_body_markdown" => "",
          "excerpt" => ""
        }
      })

      assert_push_event(view, "fill_derived", %{id: "post_excerpt", value: "Seed body paragraph."})
    end

    test "pushes the title's slug when a draft's slug is cleared", %{conn: conn} do
      {view, _post} = open_draft(conn, %{title: "Custom Draft", slug: "my-own-slug"})

      render_change(view, "validate", %{
        "post" => %{"title" => "Custom Draft", "_unused_title" => "", "slug" => ""}
      })

      assert_push_event(view, "fill_derived", %{id: "post_slug", value: "custom-draft"})
    end

    test "pushes nothing for an ordinary keystroke", %{conn: conn} do
      {view, _post} =
        open_draft(conn, %{body_markdown: "Seed body paragraph.", excerpt: "Custom words"})

      render_change(view, "validate", %{
        "post" => %{
          "title" => "Untitled post",
          "_unused_title" => "",
          "slug" => "untitled-post",
          "_unused_slug" => "",
          "body_markdown" => "Seed body paragraph.",
          "_unused_body_markdown" => "",
          "excerpt" => "Custom wordsx"
        }
      })

      refute_push_event(view, "fill_derived", %{})
    end

    test "pushes nothing when a published post's slug is cleared", %{conn: conn} do
      {view, _post} =
        open_draft(conn, %{
          title: "Live Title",
          slug: "live-slug",
          published_at: ~U[2026-01-01 00:00:00Z]
        })

      render_change(view, "validate", %{
        "post" => %{"title" => "Live Title", "_unused_title" => "", "slug" => ""}
      })

      refute_push_event(view, "fill_derived", %{id: "post_slug"})
    end
  end

  test "a post loaded with a blank excerpt autofills it from the body", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Blank Excerpt",
        slug: "blank-excerpt",
        body_markdown: "Stored body."
      })

    post |> Ecto.Changeset.change(excerpt: "") |> Newton.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    html =
      render_change(view, "validate", %{
        "post" => %{
          "body_markdown" => "Edited body.",
          "excerpt" => "",
          "_unused_excerpt" => ""
        }
      })

    assert excerpt_value(html) == "Edited body."
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

  test "publishing a brand-new post creates it published and serves it publicly", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts/new")

    render_change(view, "validate", %{
      "post" => %{"title" => "Straight Out", "slug" => "", "body_markdown" => "Fresh"}
    })

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish now") |> render_click()

    post = Newton.Blog.get_post_by_slug!("straight-out")
    assert post.title == "Straight Out"
    assert Newton.Blog.publish_status(post.published_at) == :published
    assert_patch(view, ~p"/admin/posts/#{post.id}/edit")

    assert build_conn() |> get(~p"/posts/#{post.slug}") |> html_response(200)
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

  test "a crafted validate payload cannot publish a draft through autosave", %{conn: conn} do
    {view, post} = open_draft(conn)

    render_change(view, "validate", %{
      "post" => %{
        "title" => post.title,
        "slug" => post.slug,
        "body_markdown" => "smuggling a publish",
        "published_at" => "2020-01-01T00:00:00Z"
      }
    })

    send(view.pid, :autosave)
    render(view)

    reloaded = Newton.Blog.get_post!(post.id)
    assert reloaded.body_markdown == "smuggling a publish"
    assert is_nil(reloaded.published_at)
  end

  test "a crafted validate payload cannot rewrite the preview token", %{conn: conn} do
    {view, post} = open_draft(conn)
    {:ok, post} = Newton.Blog.enable_preview(post)

    render_change(view, "validate", %{
      "post" => %{
        "title" => post.title,
        "slug" => post.slug,
        "body_markdown" => "body",
        "preview_token" => "attacker-chosen-token"
      }
    })

    send(view.pid, :autosave)
    render(view)

    assert Newton.Blog.get_post!(post.id).preview_token == post.preview_token
  end
end
