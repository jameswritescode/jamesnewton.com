defmodule NewtonWeb.Admin.GalleryShowLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures
  import Newton.GalleryFixtures

  alias Newton.Gallery

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "shows the gallery title and its photos", %{conn: conn} do
    group = group_fixture(%{title: "Trip"})
    photo = photo_fixture(group, %{alt: "A boat"})

    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    assert has_element?(view, "h1", "Trip")
    assert has_element?(view, "#photo-#{photo.id}")
  end

  test "flags photos that are missing alt text", %{conn: conn} do
    group = group_fixture()
    blank = photo_fixture(group, %{alt: ""})
    described = photo_fixture(group, %{alt: "Described"})

    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    assert has_element?(view, "#photo-#{blank.id} [data-role=needs-alt]")
    refute has_element?(view, "#photo-#{described.id} [data-role=needs-alt]")
  end
end
