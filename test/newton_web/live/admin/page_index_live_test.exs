defmodule NewtonWeb.Admin.PageIndexLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "lists existing pages", %{conn: conn} do
    {:ok, _page} =
      Newton.Pages.create_page(%{
        slug: "about",
        title: "About",
        body_markdown: "",
        published: true
      })

    {:ok, view, _html} = live(conn, ~p"/admin/pages")

    assert has_element?(view, "#pages")
    assert render(view) =~ "About"
  end

  test "clicking a page row navigates to its editor", %{conn: conn} do
    {:ok, page} =
      Newton.Pages.create_page(%{
        slug: "about",
        title: "About",
        body_markdown: "",
        published: false
      })

    {:ok, view, _html} = live(conn, ~p"/admin/pages")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("#pages-#{page.id} a") |> render_click()

    assert to == "/admin/pages/#{page.id}/edit"
  end
end
