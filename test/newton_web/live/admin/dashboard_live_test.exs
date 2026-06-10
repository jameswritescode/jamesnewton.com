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
end
