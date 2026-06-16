defmodule NewtonWeb.Admin.AdminShellTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "the admin shell renders the mobile nav toggle wired to the drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-nav-toggle[phx-hook='AdminNav']")
    assert has_element?(view, "#admin-sidebar")
    assert has_element?(view, "#admin-sidebar-backdrop")
  end

  test "the sidebar still holds the nav and account actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-sidebar a", "Posts")
    assert has_element?(view, "#admin-sidebar a", "Log out")
  end
end
