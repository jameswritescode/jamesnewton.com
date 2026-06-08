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
end
