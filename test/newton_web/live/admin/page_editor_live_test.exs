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

  test "editing a draft persists on submit", %{conn: conn} do
    {view, _page} = open_draft(conn)

    view
    |> form("#page-form", page: %{title: "About", slug: "about", body_markdown: "Body copy."})
    |> render_submit()

    page = Newton.Pages.get_page_by_slug("about")
    assert page.body_html =~ "Body copy."
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

  test "publishing a draft makes it reachable at its public slug", %{conn: conn} do
    {view, _page} = open_draft(conn, %{slug: "colophon"})

    view
    |> form("#page-form",
      page: %{
        title: "Colophon",
        slug: "colophon",
        body_markdown: "How this site is built.",
        published: true
      }
    )
    |> render_submit()

    public = get(build_conn(), "/colophon")
    assert html_response(public, 200) =~ "Colophon"
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

    view
    |> element("#page-delete")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/pages")

    assert_raise Ecto.NoResultsError, fn -> Newton.Pages.get_page!(page.id) end
  end
end
