defmodule NewtonWeb.Admin.GalleryIndexLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures
  import Newton.GalleryFixtures

  alias Newton.Gallery

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "lists galleries", %{conn: conn} do
    group = group_fixture(%{title: "Eastern Sierra"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos")
    assert has_element?(view, "#galleries-#{group.id}", "Eastern Sierra")
  end
end
