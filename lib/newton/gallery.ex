defmodule Newton.Gallery do
  @moduledoc "Photo groups and photos; resolves image keys to URLs."
  import Ecto.Query, warn: false
  alias Newton.Gallery.{Photo, PhotoGroup}
  alias Newton.Repo

  def create_group(attrs) do
    %PhotoGroup{} |> PhotoGroup.changeset(attrs) |> Repo.insert()
  end

  def add_photo(%PhotoGroup{id: group_id}, attrs) do
    attrs = Map.put(attrs, :photo_group_id, group_id)
    %Photo{} |> Photo.changeset(attrs) |> Repo.insert()
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
