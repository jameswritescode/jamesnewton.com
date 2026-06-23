defmodule Newton.GalleryTest do
  use Newton.DataCase
  alias Newton.Gallery
  alias Newton.Gallery.Storage
  import Newton.GalleryFixtures

  test "image_url passes absolute URLs through" do
    assert Gallery.image_url("https://example.com/a.jpg") == "https://example.com/a.jpg"
  end

  test "image_url maps a stored key to /media" do
    assert Gallery.image_url("eastern-sierra/01.jpg") == "/media/eastern-sierra/01.jpg"
  end

  test "list_groups returns groups newest-first with ordered photos preloaded" do
    {:ok, g} =
      Gallery.create_group(%{
        slug: "eastern-sierra",
        title: "Eastern Sierra",
        taken_on: ~D[2025-06-01]
      })

    {:ok, _} = Gallery.add_photo(g, %{image_key: "b.jpg", alt: "B", position: 2})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "a.jpg", alt: "A", position: 1})

    [group] = Gallery.list_groups()
    assert group.slug == "eastern-sierra"
    assert Enum.map(group.photos, & &1.image_key) == ["a.jpg", "b.jpg"]
  end

  test "recent_groups/1 excludes undated groups, newest first, limited" do
    {:ok, _} = Gallery.create_group(%{slug: "undated", title: "Undated", taken_on: nil})
    {:ok, _} = Gallery.create_group(%{slug: "older", title: "Older", taken_on: ~D[2024-01-01]})
    {:ok, _} = Gallery.create_group(%{slug: "newer", title: "Newer", taken_on: ~D[2025-01-01]})

    assert Gallery.recent_groups(5) |> Enum.map(& &1.slug) == ["newer", "older"]
    assert Gallery.recent_groups(1) |> Enum.map(& &1.slug) == ["newer"]
  end

  test "count_groups/0 and count_photos/0" do
    {:ok, g} = Gallery.create_group(%{slug: "walk", title: "Walk"})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "a.jpg", alt: "A", position: 0})
    {:ok, _} = Gallery.add_photo(g, %{image_key: "b.jpg", alt: "B", position: 1})

    assert Gallery.count_groups() == 1
    assert Gallery.count_photos() == 2
  end

  test "a photo may be created with blank alt" do
    {:ok, g} = Gallery.create_group(%{slug: "blank-alt", title: "Blank Alt"})
    assert {:ok, photo} = Gallery.add_photo(g, %{image_key: "x.jpg", alt: "", position: 0})
    assert photo.alt == ""
  end

  test "get_group!/1, update_group/2, change_group/2" do
    group = group_fixture(%{title: "Orig"})
    assert Gallery.get_group!(group.id).id == group.id
    {:ok, updated} = Gallery.update_group(group, %{title: "New"})
    assert updated.title == "New"
    assert %Ecto.Changeset{} = Gallery.change_group(group)
  end

  test "get_group_by_slug!/1 finds by slug" do
    group = group_fixture(%{slug: "find-me"})
    assert Gallery.get_group_by_slug!("find-me").id == group.id
  end

  test "photo get/update/change" do
    group = group_fixture()
    photo = photo_fixture(group, %{alt: "old"})
    assert Gallery.get_photo!(photo.id).id == photo.id
    {:ok, updated} = Gallery.update_photo(photo, %{alt: "new"})
    assert updated.alt == "new"
    assert %Ecto.Changeset{} = Gallery.change_photo(photo)
  end

  test "update_photo only changes alt, ignoring server-owned fields" do
    group = group_fixture()
    other = group_fixture()
    photo = photo_fixture(group, %{image_key: "orig.jpg", position: 0, alt: "old"})

    {:ok, updated} =
      Gallery.update_photo(photo, %{
        "alt" => "new alt",
        "image_key" => "../../etc/passwd",
        "photo_group_id" => other.id,
        "position" => 99,
        "width" => 1,
        "height" => 1
      })

    assert updated.alt == "new alt"
    assert updated.image_key == "orig.jpg"
    assert updated.photo_group_id == group.id
    assert updated.position == 0
  end

  test "next_position/1 returns max position + 1, or 0 when empty" do
    group = group_fixture()
    assert Gallery.next_position(group) == 0
    photo_fixture(group, %{position: 5})
    assert Gallery.next_position(group) == 6
  end

  test "delete_photo/1 removes the row and the file" do
    group = group_fixture()
    key = stored_image()
    photo = photo_fixture(group, %{image_key: key})

    {:ok, _} = Gallery.delete_photo(photo)
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute File.exists?(Path.join(media_root(), key))
  end

  test "delete_group/1 removes the group, its photos, and their files" do
    group = group_fixture()
    key = stored_image()
    photo = photo_fixture(group, %{image_key: key})

    {:ok, _} = Gallery.delete_group(group)
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_group!(group.id) end
    assert_raise Ecto.NoResultsError, fn -> Gallery.get_photo!(photo.id) end
    refute File.exists?(Path.join(media_root(), key))
  end

  test "reorder_photos/2 sets position to match the given id order" do
    group = group_fixture()
    a = photo_fixture(group, %{position: 0})
    b = photo_fixture(group, %{position: 1})
    c = photo_fixture(group, %{position: 2})

    :ok = Gallery.reorder_photos(group, [c.id, a.id, b.id])

    ordered = Gallery.get_group!(group.id).photos |> Enum.map(& &1.id)
    assert ordered == [c.id, a.id, b.id]
  end

  test "reorder_photos/2 ignores ids that belong to another gallery" do
    group = group_fixture()
    other = group_fixture()
    a = photo_fixture(group, %{position: 0})
    foreign = photo_fixture(other, %{position: 0})

    :ok = Gallery.reorder_photos(group, [foreign.id, a.id])

    assert Gallery.get_photo!(foreign.id).position == 0
    assert Gallery.get_photo!(a.id).position in 0..1
  end

  test "add_photo persists a thumb_key" do
    group = group_fixture()

    {:ok, photo} =
      Gallery.add_photo(group, %{image_key: "k.jpg", thumb_key: "t.webp", alt: "", position: 0})

    assert photo.thumb_key == "t.webp"
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_image do
    root = media_root()
    File.mkdir_p!(root)
    src = Path.join(root, "src-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "data")
    {:ok, key} = Storage.store(src, "p.jpg")
    File.rm(src)
    key
  end
end
