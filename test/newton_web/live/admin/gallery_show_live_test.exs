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

  test "uploading a photo adds it to the gallery with captured dimensions", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    photo =
      file_input(view, "#upload-form", :photos, [
        %{name: "shot.jpg", content: "fakeimage", type: "image/jpeg"}
      ])

    render_hook(view, "set_dimensions", %{"name" => "shot.jpg", "width" => 1200, "height" => 800})
    render_upload(photo, "shot.jpg")
    view |> element("#upload-form") |> render_submit()

    [created] = Gallery.get_group!(group.id).photos
    assert created.width == 1200
    assert created.height == 800
    assert has_element?(view, "#photo-#{created.id}")
  end

  test "editing alt text clears the needs-alt badge", %{conn: conn} do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: ""})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/photo/#{photo.id}")

    view |> form("#photo-form", photo: %{alt: "A described photo"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos/#{group.id}")
    assert Gallery.get_photo!(photo.id).alt == "A described photo"
    refute has_element?(view, "#photo-#{photo.id} [data-role=needs-alt]")
  end

  test "deleting a photo removes it from the grid", %{conn: conn} do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: "x"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/photo/#{photo.id}")

    view |> element("#photo-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/photos/#{group.id}")
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute has_element?(view, "#photo-#{photo.id}")
  end

  test "reorder event persists the new photo order", %{conn: conn} do
    group = group_fixture()
    a = photo_fixture(group, %{position: 0})
    b = photo_fixture(group, %{position: 1})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    render_hook(view, "reorder", %{"ids" => ["#{b.id}", "#{a.id}"]})

    ordered = Gallery.get_group!(group.id).photos |> Enum.map(& &1.id)
    assert ordered == [b.id, a.id]
  end

  test "Settings opens the gallery drawer on the gallery page, not the list", %{conn: conn} do
    group = group_fixture(%{title: "Trip"})
    photo = photo_fixture(group)
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    view |> element(~s(a[href$="/edit"]), "Settings") |> render_click()

    assert_patch(view, ~p"/admin/photos/#{group.id}/edit")
    # Still on the gallery page: the photo grid and the settings drawer coexist.
    assert has_element?(view, "#gallery-drawer #gallery-form")
    assert has_element?(view, "#photo-#{photo.id}")
  end

  test "saving gallery settings updates it and stays on the gallery page", %{conn: conn} do
    group = group_fixture(%{title: "Old"})
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view |> form("#gallery-form", group: %{title: "Renamed"}) |> render_submit()

    assert_patch(view, ~p"/admin/photos/#{group.id}")
    assert Gallery.get_group!(group.id).title == "Renamed"
    assert has_element?(view, "h1", "Renamed")
  end

  test "deleting a gallery from settings returns to the list", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}/edit")

    view
    |> element("#gallery-drawer button", "Delete")
    |> render_click()
    |> follow_redirect(conn, ~p"/admin/photos")

    assert_raise Ecto.NoResultsError, fn -> Gallery.get_group!(group.id) end
  end
end
