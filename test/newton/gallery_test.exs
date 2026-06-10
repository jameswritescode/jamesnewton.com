defmodule Newton.GalleryTest do
  use Newton.DataCase
  alias Newton.Gallery

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
end
