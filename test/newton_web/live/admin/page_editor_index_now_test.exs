defmodule NewtonWeb.Admin.PageEditorIndexNowTest do
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    config = Application.get_env(:newton, Newton.IndexNow)
    Application.put_env(:newton, Newton.IndexNow, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, Newton.IndexNow, config) end)

    test_pid = self()

    Req.Test.stub(Newton.IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:indexnow_request, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  defp open_page(conn, attrs) do
    {:ok, page} =
      Newton.Pages.create_page(
        Enum.into(attrs, %{title: "About", slug: "about", body_markdown: "Hello."})
      )

    {:ok, view, _html} = live(conn, ~p"/admin/pages/#{page.id}/edit")
    {view, page}
  end

  defp assert_submitted(urls) do
    assert_receive {:indexnow_request, %{"urlList" => submitted}}, 2_000
    assert Enum.sort(submitted) == Enum.sort(urls)
  end

  test "publishing an opted-in page submits only its URL", %{conn: conn} do
    {view, _page} = open_page(conn, %{in_sitemap: true})

    render_click(view, "publish", %{})

    assert_submitted([url(~p"/about")])
  end

  test "publishing an opted-out page submits nothing", %{conn: conn} do
    {view, _page} = open_page(conn, %{in_sitemap: false})

    render_click(view, "publish", %{})

    refute_receive {:indexnow_request, _}, 200
  end

  test "editing a draft submits nothing", %{conn: conn} do
    {view, _page} = open_page(conn, %{in_sitemap: true})

    view
    |> form("#page-form", page: %{title: "About", slug: "about", body_markdown: "Edited."})
    |> render_submit()

    refute_receive {:indexnow_request, _}, 200
  end

  test "saving a renamed published page submits the old and new URLs", %{conn: conn} do
    {view, _page} = open_page(conn, %{published: true, in_sitemap: true})

    view
    |> form("#page-form", page: %{title: "About", slug: "colophon", body_markdown: "Hello."})
    |> render_submit()

    assert_submitted([url(~p"/about"), url(~p"/colophon")])
  end

  test "moving an opted-in page to draft submits its URL", %{conn: conn} do
    {view, _page} = open_page(conn, %{published: true, in_sitemap: true})

    render_click(view, "unpublish", %{})

    assert_submitted([url(~p"/about")])
  end

  test "toggling the sitemap opt-in on and off submits the URL each time", %{conn: conn} do
    {view, _page} = open_page(conn, %{published: true, in_sitemap: false})

    render_click(view, "toggle_sitemap", %{})
    assert_submitted([url(~p"/about")])

    render_click(view, "toggle_sitemap", %{})
    assert_submitted([url(~p"/about")])
  end

  test "deleting an opted-in page submits its URL", %{conn: conn} do
    {view, _page} = open_page(conn, %{published: true, in_sitemap: true})

    render_click(view, "delete", %{})

    assert_submitted([url(~p"/about")])
  end
end
