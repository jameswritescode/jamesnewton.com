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

  test "creates a gallery and shows it in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/photos/new")

    view |> form("#gallery-form", group: %{title: "New Gallery"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos")
    assert has_element?(view, "#galleries", "New Gallery")
    assert Enum.any?(Gallery.list_groups(), &(&1.title == "New Gallery"))
  end

  test "slug auto-derives from the title until edited", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/photos/new")
    html = view |> form("#gallery-form", group: %{title: "Hello World", slug: ""}) |> render_change()
    assert html =~ ~s(value="hello-world")
  end

  test "edits a gallery", %{conn: conn} do
    group = group_fixture(%{title: "Old"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view |> form("#gallery-form", group: %{title: "Renamed"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos")
    assert Gallery.get_group!(group.id).title == "Renamed"
  end

  test "deletes a gallery from the drawer", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view |> element("#gallery-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/photos")
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_group!(group.id) end
  end
end
