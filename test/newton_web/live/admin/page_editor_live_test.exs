defmodule NewtonWeb.Admin.PageEditorLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  @png_1x1 <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
             8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0,
             0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp open_draft(conn, attrs \\ %{}) do
    {:ok, page} =
      Newton.Pages.create_page(
        Enum.into(attrs, %{title: "Untitled", slug: "untitled-page", body_markdown: ""})
      )

    {:ok, view, _html} = live(conn, ~p"/admin/pages/#{page.id}/edit")
    {view, page}
  end

  test "client-rejected files surface as a flash", %{conn: conn} do
    {view, _page} = open_draft(conn)

    render_hook(view, "upload_rejected", %{
      "rejected" => [
        %{"name" => "big.png", "reason" => "size"},
        %{"name" => "vector.svg", "reason" => "type"}
      ]
    })

    assert has_element?(view, "#admin-flash-error", "big.png (larger than 50MB)")
    assert has_element?(view, "#admin-flash-error", "vector.svg (unsupported type)")
  end

  test "editing a draft persists on submit", %{conn: conn} do
    {view, _page} = open_draft(conn)

    view
    |> form("#page-form", page: %{title: "About", slug: "about", body_markdown: "Body copy."})
    |> render_submit()

    page = Newton.Pages.get_page_by_slug("about")
    assert page.body_html =~ "Body copy."
  end

  test "the settings drawer toggles sitemap inclusion immediately", %{conn: conn} do
    {view, page} = open_draft(conn)

    render_click(view, "toggle_drawer")
    view |> element("#sitemap-toggle") |> render_click()
    assert Newton.Pages.get_page!(page.id).in_sitemap

    view |> element("#sitemap-toggle") |> render_click()
    refute Newton.Pages.get_page!(page.id).in_sitemap
  end

  test "a draft auto-saves without a manual save", %{conn: conn} do
    {view, page} = open_draft(conn)

    view
    |> form("#page-form",
      page: %{title: "Untitled", slug: "untitled-page", body_markdown: "new body"}
    )
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Pages.get_page!(page.id).body_html =~ "new body"
  end

  test "an inline upload lands on the page's image ledger and pushes insert_image", %{conn: conn} do
    {view, page} = open_draft(conn)

    image =
      file_input(view, "#page-form", :inline_images, [
        %{name: "shot.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "shot.png")

    assert [attached] = Newton.Pages.list_images(page)
    assert_push_event(view, "insert_image", %{url: url, name: "shot.png"})
    assert url == "/media/" <> attached.key
  end

  test "a reserved slug shows a form error", %{conn: conn} do
    {view, _page} = open_draft(conn)

    html =
      view
      |> form("#page-form", page: %{title: "Nope", slug: "admin", body_markdown: ""})
      |> render_submit()

    assert html =~ "reserved"
  end

  test "a new page autosaves into a draft and moves to its edit URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{
      "page" => %{"title" => "Colophon", "slug" => "colophon", "body_markdown" => "Hello body"}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    page = Newton.Pages.get_page_by_slug("colophon")
    assert page.body_html =~ "Hello body"
    assert_patch(view, ~p"/admin/pages/#{page.id}/edit")
  end

  test "a brand-new page creates no row until there is content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{"page" => %{"title" => "", "body_markdown" => ""}})
    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Pages.list_pages() == []
  end

  test "the first upload on a brand-new page creates the draft and attaches to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    image =
      file_input(view, "#page-form", :inline_images, [
        %{name: "first.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "first.png")
    assert_patch(view)

    assert [page] = Newton.Pages.list_pages()
    assert [%{original_filename: "first.png"}] = Newton.Pages.list_images(page)
    assert_push_event(view, "insert_image", %{url: "/media/" <> _})
  end

  test "the first upload keeps a title typed on a brand-new page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{
      "page" => %{
        "title" => "Kept Title",
        "slug" => "",
        "_unused_slug" => "",
        "body_markdown" => ""
      }
    })

    image =
      file_input(view, "#page-form", :inline_images, [
        %{name: "kept.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "kept.png")
    assert_patch(view)

    assert [page] = Newton.Pages.list_pages()
    assert page.title == "Kept Title"
    assert page.slug == "kept-title"
    assert has_element?(view, "#page-form input[name='page[title]'][value='Kept Title']")
  end

  test "the first upload on an untitled page creates an Untitled draft", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    image =
      file_input(view, "#page-form", :inline_images, [
        %{name: "untitled.png", content: @png_1x1, type: "image/png"}
      ])

    render_upload(image, "untitled.png")
    assert_patch(view)

    assert [%{title: "Untitled" <> _}] = Newton.Pages.list_pages()
  end

  describe "the first image on an empty new page" do
    test "shows the created draft's identity in the same reply", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

      html = upload_inline_image(view, "identity.png")

      [page] = Newton.Pages.list_pages()
      assert input_value(html, "page[title]") == "Untitled"
      assert input_value(html, "page[slug]") == page.slug
    end

    test "keeps the identity when a stale blank change follows", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

      upload_inline_image(view, "stale-identity.png")
      assert_patch(view)

      html =
        render_change(view, "validate", %{
          "page" => %{
            "title" => "",
            "_unused_title" => "",
            "slug" => "",
            "_unused_slug" => "",
            "meta_description" => "",
            "_unused_meta_description" => "",
            "body_markdown" => "![](/media/x.png)"
          }
        })

      assert input_value(html, "page[title]") == "Untitled"
      assert input_value(html, "page[slug]") =~ ~r/\Auntitled/
    end
  end

  defp input_value(html, name) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[name='#{name}']")
    |> LazyHTML.attribute("value")
    |> List.first()
  end

  describe "a blank slug on a new page" do
    test "is derived from the title when the first image creates the draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

      render_change(view, "validate", %{
        "page" => %{"title" => "Cleared Slug", "slug" => "", "_unused_slug" => ""}
      })

      render_change(view, "validate", %{
        "page" => %{"title" => "Cleared Slug", "slug" => "", "body_markdown" => ""}
      })

      upload_inline_image(view, "cleared.png")
      assert_patch(view)

      assert [page] = Newton.Pages.list_pages()
      assert page.slug == "cleared-slug"
      assert [%{original_filename: "cleared.png"}] = Newton.Pages.list_images(page)
    end

    test "is derived from the title on manual save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

      view
      |> form("#page-form", page: %{title: "Saved Blank", slug: "", body_markdown: ""})
      |> render_submit()

      assert [%{slug: "saved-blank"}] = Newton.Pages.list_pages()
    end

    test "keeps following the title when a stale blank slug arrives after the first image",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

      render_change(view, "validate", %{
        "page" => %{"title" => "Cleared Slug", "slug" => "", "_unused_slug" => ""}
      })

      upload_inline_image(view, "stale.png")
      assert_patch(view)

      render_change(view, "validate", %{
        "page" => %{"title" => "Cleared Slug", "slug" => "", "body_markdown" => "![](x)"}
      })

      assert has_element?(view, "#page-form input[name='page[slug]'][value='cleared-slug']")

      render_change(view, "validate", %{
        "page" => %{"title" => "Renamed", "slug" => "cleared-slug", "body_markdown" => "![](x)"}
      })

      assert has_element?(view, "#page-form input[name='page[slug]'][value='renamed']")
    end

    test "refills from the title when cleared on a draft", %{conn: conn} do
      {view, _page} = open_draft(conn, %{title: "Custom Draft", slug: "my-own-slug"})

      render_change(view, "validate", %{"page" => %{"title" => "Custom Draft", "slug" => ""}})

      assert has_element?(view, "#page-form input[name='page[slug]'][value='custom-draft']")

      render_change(view, "validate", %{
        "page" => %{"title" => "Retitled Draft", "slug" => "custom-draft"}
      })

      assert has_element?(view, "#page-form input[name='page[slug]'][value='retitled-draft']")
    end

    test "is not derived from the title once published", %{conn: conn} do
      {view, _page} = open_draft(conn, %{title: "Live Title", slug: "live-slug", published: true})

      render_change(view, "validate", %{"page" => %{"title" => "Live Title", "slug" => ""}})

      refute has_element?(view, "#page-form input[name='page[slug]'][value='live-title']")
    end
  end

  test "an Untitled draft from a first image takes its slug from the title typed later",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    upload_inline_image(view, "placeholder.png")
    assert_patch(view)

    [page] = Newton.Pages.list_pages()
    assert "untitled-page-" <> _ = page.slug

    render_change(view, "validate", %{
      "page" => %{"title" => "Real Title", "slug" => page.slug, "_unused_slug" => ""}
    })

    assert has_element?(view, "#page-form input[name='page[slug]'][value='real-title']")

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Pages.get_page!(page.id).slug == "real-title"
  end

  test "an Untitled draft keeps its generated slug until a real title is typed",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    upload_inline_image(view, "placeholder.png")
    assert_patch(view)

    [page] = Newton.Pages.list_pages()

    render_change(view, "validate", %{
      "page" => %{"title" => "Untitled", "slug" => page.slug, "body_markdown" => "Some words."}
    })

    assert has_element?(view, "#page-form input[name='page[slug]'][value='#{page.slug}']")

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert Newton.Pages.get_page!(page.id).slug == page.slug
  end

  test "a slug collision on the first image shows the error and creates nothing",
       %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{title: "Elsewhere", slug: "taken"})
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{
      "page" => %{"title" => "Taken", "slug" => "", "_unused_slug" => "", "body_markdown" => ""}
    })

    upload_inline_image(view, "collide.png")

    assert [%{title: "Elsewhere"}] = Newton.Pages.list_pages()
    assert has_element?(view, slug_error_selector(), "has already been taken")
    assert has_element?(view, "#page-form input[name='page[title]'][value='Taken']")
  end

  test "a slug collision on a new page's autosave shows the error", %{conn: conn} do
    {:ok, _} = Newton.Pages.create_page(%{title: "Elsewhere", slug: "taken"})
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{
      "page" => %{"title" => "Taken", "slug" => "", "_unused_slug" => "", "body_markdown" => ""}
    })

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    assert [%{title: "Elsewhere"}] = Newton.Pages.list_pages()
    assert has_element?(view, slug_error_selector(), "has already been taken")
  end

  defp slug_error_selector, do: "#page-form .fieldset:has(input[name='page[slug]']) p"

  defp upload_inline_image(view, name) do
    view
    |> file_input("#page-form", :inline_images, [
      %{name: name, content: @png_1x1, type: "image/png"}
    ])
    |> render_upload(name)
  end

  test "a published page is not auto-saved", %{conn: conn} do
    {view, page} = open_draft(conn, %{slug: "live-page", published: true})

    view
    |> form("#page-form",
      page: %{title: "Untitled", slug: "live-page", body_markdown: "changed"}
    )
    |> render_change()

    send(view.pid, :autosave)
    _ = :sys.get_state(view.pid)

    refute Newton.Pages.get_page!(page.id).body_html =~ "changed"
  end

  test "publishing from the drawer makes the page reachable at its public slug", %{conn: conn} do
    {view, _page} =
      open_draft(conn, %{
        title: "Colophon",
        slug: "colophon",
        body_markdown: "How this site is built."
      })

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish") |> render_click()

    public = get(build_conn(), "/colophon")
    assert html_response(public, 200) =~ "Colophon"
  end

  test "moving a published page to draft takes it off the public site", %{conn: conn} do
    {view, _page} = open_draft(conn, %{title: "Colophon", slug: "colophon", published: true})

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Move to draft") |> render_click()

    assert_error_sent 404, fn -> get(build_conn(), "/colophon") end
  end

  test "publishing a brand-new page creates the draft and publishes it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/pages/new")

    render_change(view, "validate", %{
      "page" => %{"title" => "Now", "slug" => "now", "body_markdown" => "Fresh."}
    })

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish") |> render_click()

    page = Newton.Pages.get_page_by_slug("now")
    assert page.published
    assert_patch(view, ~p"/admin/pages/#{page.id}/edit")
  end

  test "the slug follows the title until it is edited", %{conn: conn} do
    {view, _page} = open_draft(conn, %{title: "Untitled page", slug: "untitled-page"})

    html =
      view
      |> form("#page-form", page: %{title: "My Colophon!", slug: "untitled-page"})
      |> render_change()

    assert html =~ ~s(value="my-colophon")

    view
    |> form("#page-form", page: %{title: "My Colophon!", slug: "custom"})
    |> render_change()

    html =
      view
      |> form("#page-form", page: %{title: "My Colophon Again", slug: "custom"})
      |> render_change()

    assert html =~ ~s(value="custom")
  end

  test "the slug stops following the title once the page is published", %{conn: conn} do
    {view, _page} = open_draft(conn, %{title: "Untitled page", slug: "untitled-page"})

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish") |> render_click()

    html =
      view
      |> form("#page-form", page: %{title: "Renamed Page", slug: "untitled-page"})
      |> render_change()

    assert html =~ ~s(value="untitled-page")
  end

  test "the meta description follows the body until it is edited", %{conn: conn} do
    {view, _page} = open_draft(conn, %{title: "Untitled page", slug: "untitled-page"})

    html =
      view
      |> form("#page-form", page: %{body_markdown: "The first paragraph of the body."})
      |> render_change()

    assert meta_value(html) == "The first paragraph of the body."

    view
    |> form("#page-form",
      page: %{body_markdown: "Different body now.", meta_description: "My own summary"}
    )
    |> render_change()

    html =
      view
      |> form("#page-form",
        page: %{body_markdown: "Changed again.", meta_description: "My own summary"}
      )
      |> render_change()

    assert meta_value(html) == "My own summary"
  end

  test "the meta description follows the body while the field stays untouched", %{conn: conn} do
    {view, _page} = open_draft(conn, %{title: "Untitled page", slug: "untitled-page"})
    stale = "Seed body paragraph."

    render_change(view, "validate", %{
      "page" => %{
        "body_markdown" => "Second body version.",
        "meta_description" => stale,
        "_unused_meta_description" => ""
      }
    })

    html =
      render_change(view, "validate", %{
        "page" => %{
          "body_markdown" => "Third body version now.",
          "meta_description" => stale,
          "_unused_meta_description" => ""
        }
      })

    assert meta_value(html) == "Third body version now."
  end

  describe "a cleared meta description" do
    test "re-derives from the body and keeps following it", %{conn: conn} do
      {view, _page} = open_draft(conn, %{body_markdown: "Seed body paragraph."})

      render_change(view, "validate", %{
        "page" => %{"body_markdown" => "Seed body paragraph.", "meta_description" => "Custom"}
      })

      html =
        render_change(view, "validate", %{
          "page" => %{"body_markdown" => "Seed body paragraph.", "meta_description" => ""}
        })

      assert meta_value(html) == "Seed body paragraph."

      html =
        render_change(view, "validate", %{
          "page" => %{
            "body_markdown" => "A newer body.",
            "meta_description" => "Seed body paragraph.",
            "_unused_meta_description" => ""
          }
        })

      assert meta_value(html) == "A newer body."
    end

    test "locks again once the author types a custom value", %{conn: conn} do
      {view, _page} = open_draft(conn, %{body_markdown: "Seed body paragraph."})

      render_change(view, "validate", %{
        "page" => %{"body_markdown" => "Seed body paragraph.", "meta_description" => ""}
      })

      render_change(view, "validate", %{
        "page" => %{"body_markdown" => "Seed body paragraph.", "meta_description" => "Mine now"}
      })

      html =
        render_change(view, "validate", %{
          "page" => %{
            "body_markdown" => "A newer body.",
            "meta_description" => "Mine now",
            "_unused_meta_description" => ""
          }
        })

      assert meta_value(html) == "Mine now"
    end
  end

  test "a page loaded with a blank meta description autofills it from the body", %{conn: conn} do
    {view, _page} = open_draft(conn, %{body_markdown: "Stored body.", meta_description: ""})

    html =
      render_change(view, "validate", %{
        "page" => %{
          "body_markdown" => "Edited body.",
          "meta_description" => "",
          "_unused_meta_description" => ""
        }
      })

    assert meta_value(html) == "Edited body."
  end

  defp meta_value(html) do
    case Regex.run(
           ~r/<textarea[^>]*name="page\[meta_description\]"[^>]*>([^<]*)<\/textarea>/,
           html
         ) do
      [_, content] -> String.trim(content)
      _ -> :no_meta_textarea
    end
  end

  test "a submit against a version another window already saved shows the conflict banner", %{
    conn: conn
  } do
    {view_a, page} = open_draft(conn)
    {:ok, view_b, _html} = live(conn, ~p"/admin/pages/#{page.id}/edit")

    view_a
    |> form("#page-form",
      page: %{title: "Untitled", slug: "untitled-page", body_markdown: "saved from A"}
    )
    |> render_change()

    send(view_a.pid, :autosave)
    _ = :sys.get_state(view_a.pid)

    view_b
    |> form("#page-form", page: %{title: "From B", slug: "untitled-page", body_markdown: ""})
    |> render_submit()

    assert has_element?(view_b, "#page-conflict-banner")
  end

  test "delete removes the page and navigates to the index", %{conn: conn} do
    {view, page} = open_draft(conn)

    view |> element("button", "Settings") |> render_click()

    view
    |> element("#publish-drawer button", "Delete")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/pages")

    assert_raise Ecto.NoResultsError, fn -> Newton.Pages.get_page!(page.id) end
  end
end
