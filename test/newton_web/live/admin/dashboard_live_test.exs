defmodule NewtonWeb.Admin.DashboardLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "renders the three summary cards with counts", %{conn: conn} do
    {:ok, _} = Newton.Blog.create_post(%{title: "Draft", slug: "d", body_markdown: "x"})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#card-posts")
    assert has_element?(view, "#card-reading")
    assert has_element?(view, "#card-photos")
    assert has_element?(view, "#card-posts", "1")
  end

  test "renders the pages count card", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "about",
        title: "About",
        body_markdown: "",
        published: true
      })

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#card-pages", "1")
  end

  test "the pages card counts only draft pages as drafts", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{slug: "about", title: "About", published: true})

    {:ok, _} =
      Newton.Pages.create_page(%{slug: "uses", title: "Uses", published: false})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#card-pages", "1 draft")
  end
end
