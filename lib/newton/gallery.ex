defmodule Newton.Gallery do
  @moduledoc "Photo groups and photos; resolves image keys to URLs."
  import Ecto.Query, warn: false
  alias Newton.Gallery.{Photo, PhotoGroup, Storage}
  alias Newton.Repo

  def create_group(attrs) do
    %PhotoGroup{} |> PhotoGroup.changeset(attrs) |> Repo.insert()
  end

  def add_photo(%PhotoGroup{id: group_id}, attrs) do
    attrs = Map.put(attrs, :photo_group_id, group_id)
    %Photo{} |> Photo.create_changeset(attrs) |> Repo.insert()
  end

  def get_group!(id) do
    Repo.get!(PhotoGroup, id) |> Repo.preload(photos: from(p in Photo, order_by: p.position))
  end

  def get_group_by_slug!(slug) do
    Repo.get_by!(PhotoGroup, slug: slug)
    |> Repo.preload(photos: from(p in Photo, order_by: p.position))
  end

  def update_group(%PhotoGroup{} = group, attrs) do
    group |> PhotoGroup.changeset(attrs) |> Repo.update()
  end

  def change_group(%PhotoGroup{} = group, attrs \\ %{}), do: PhotoGroup.changeset(group, attrs)

  def delete_group(%PhotoGroup{} = group) do
    group = Repo.preload(group, :photos)
    Enum.each(group.photos, &Storage.delete(&1.image_key))
    Repo.delete(group)
  end

  def get_photo!(id), do: Repo.get!(Photo, id)

  def update_photo(%Photo{} = photo, attrs) do
    photo |> Photo.changeset(attrs) |> Repo.update()
  end

  def change_photo(%Photo{} = photo, attrs \\ %{}), do: Photo.changeset(photo, attrs)

  def delete_photo(%Photo{} = photo) do
    Storage.delete(photo.image_key)
    Repo.delete(photo)
  end

  def next_position(%PhotoGroup{id: group_id}) do
    case Repo.aggregate(from(p in Photo, where: p.photo_group_id == ^group_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end

  def reorder_photos(%PhotoGroup{id: group_id}, ordered_ids) do
    valid_ids =
      Repo.all(from p in Photo, where: p.photo_group_id == ^group_id, select: p.id)
      |> MapSet.new()

    ordered_ids
    |> Enum.filter(&MapSet.member?(valid_ids, &1))
    |> Enum.with_index()
    |> Enum.reduce(Ecto.Multi.new(), fn {id, index}, multi ->
      Ecto.Multi.update_all(multi, {:photo, id}, from(p in Photo, where: p.id == ^id),
        set: [position: index]
      )
    end)
    |> Repo.transaction()

    :ok
  end

  def list_groups do
    Repo.all(from g in PhotoGroup, order_by: [desc: g.taken_on], preload: [:photos])
  end

  @doc "Total number of photo groups."
  def count_groups, do: Repo.aggregate(PhotoGroup, :count)

  @doc "Total number of photos across all groups."
  def count_photos, do: Repo.aggregate(Photo, :count)

  @doc "Most recent dated photo groups, newest first, limited; photos preloaded."
  def recent_groups(limit) do
    Repo.all(
      from g in PhotoGroup,
        where: not is_nil(g.taken_on),
        order_by: [desc: g.taken_on],
        limit: ^limit,
        preload: [:photos]
    )
  end

  @doc "Resolve an image_key to a URL. Absolute URLs pass through; keys map to /media."
  def image_url("http://" <> _ = url), do: url
  def image_url("https://" <> _ = url), do: url
  def image_url(key) when is_binary(key), do: "/media/" <> key
end
