defmodule Newton.GalleryFixtures do
  alias Newton.Gallery

  def group_fixture(attrs \\ %{}) do
    {:ok, group} =
      attrs
      |> Enum.into(%{slug: "group-#{System.unique_integer([:positive])}", title: "A Gallery"})
      |> Gallery.create_group()

    group
  end

  def photo_fixture(group, attrs \\ %{}) do
    {:ok, photo} =
      Gallery.add_photo(
        group,
        Enum.into(attrs, %{
          image_key: "k-#{System.unique_integer([:positive])}.jpg",
          alt: "",
          position: 0
        })
      )

    photo
  end
end
