defmodule Newton.Gallery do
  @moduledoc "Photo groups and photos; resolves image keys to URLs."
  import Ecto.Query, warn: false
  alias Newton.Gallery.{Photo, PhotoGroup, Storage, Thumbnail}
  alias Newton.Repo

  @spec create_group(map()) :: {:ok, %PhotoGroup{}} | {:error, Ecto.Changeset.t()}
  def create_group(attrs) do
    %PhotoGroup{} |> PhotoGroup.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Generate a WebP thumbnail of the image at `source_path`, store it, and return
  its key. Cleans up the temp file. Returns `{:error, _}` if the source can't be
  thumbnailed (callers fall back to serving the original).
  """
  @spec store_thumbnail(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def store_thumbnail(source_path) do
    with {:ok, tmp} <- Thumbnail.generate(source_path),
         {:ok, key} <- Storage.store(tmp, "thumb.webp") do
      File.rm(tmp)
      {:ok, key}
    end
  end

  @spec add_photo(%PhotoGroup{}, map()) :: {:ok, %Photo{}} | {:error, Ecto.Changeset.t()}
  def add_photo(%PhotoGroup{id: group_id}, attrs) do
    attrs = Map.put(attrs, :photo_group_id, group_id)
    %Photo{} |> Photo.create_changeset(attrs) |> Repo.insert()
  end

  @spec get_group!(term()) :: %PhotoGroup{}
  def get_group!(id) do
    Repo.get!(PhotoGroup, id) |> Repo.preload(photos: from(p in Photo, order_by: p.position))
  end

  @spec get_group_by_slug!(String.t()) :: %PhotoGroup{}
  def get_group_by_slug!(slug) do
    Repo.get_by!(PhotoGroup, slug: slug)
    |> Repo.preload(photos: from(p in Photo, order_by: p.position))
  end

  @spec update_group(%PhotoGroup{}, map()) :: {:ok, %PhotoGroup{}} | {:error, Ecto.Changeset.t()}
  def update_group(%PhotoGroup{} = group, attrs) do
    group |> PhotoGroup.changeset(attrs) |> Repo.update()
  end

  @spec change_group(%PhotoGroup{}, map()) :: Ecto.Changeset.t()
  def change_group(%PhotoGroup{} = group, attrs \\ %{}), do: PhotoGroup.changeset(group, attrs)

  @spec delete_group(%PhotoGroup{}) :: {:ok, %PhotoGroup{}} | {:error, Ecto.Changeset.t()}
  def delete_group(%PhotoGroup{} = group) do
    group = Repo.preload(group, :photos)
    Enum.each(group.photos, &Storage.delete(&1.image_key))
    Repo.delete(group)
  end

  @spec get_photo!(term()) :: %Photo{}
  def get_photo!(id), do: Repo.get!(Photo, id)

  @spec update_photo(%Photo{}, map()) :: {:ok, %Photo{}} | {:error, Ecto.Changeset.t()}
  def update_photo(%Photo{} = photo, attrs) do
    photo |> Photo.changeset(attrs) |> Repo.update()
  end

  @spec change_photo(%Photo{}, map()) :: Ecto.Changeset.t()
  def change_photo(%Photo{} = photo, attrs \\ %{}), do: Photo.changeset(photo, attrs)

  @spec delete_photo(%Photo{}) :: {:ok, %Photo{}} | {:error, Ecto.Changeset.t()}
  def delete_photo(%Photo{} = photo) do
    Storage.delete(photo.image_key)
    Repo.delete(photo)
  end

  @spec next_position(%PhotoGroup{}) :: non_neg_integer()
  def next_position(%PhotoGroup{id: group_id}) do
    case Repo.aggregate(from(p in Photo, where: p.photo_group_id == ^group_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end

  @spec reorder_photos(%PhotoGroup{}, [term()]) :: :ok
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

  @spec list_groups() :: [%PhotoGroup{}]
  def list_groups do
    Repo.all(from g in PhotoGroup, order_by: [desc: g.taken_on], preload: [:photos])
  end

  @doc "Total number of photo groups."
  @spec count_groups() :: non_neg_integer()
  def count_groups, do: Repo.aggregate(PhotoGroup, :count)

  @doc "Total number of photos across all groups."
  @spec count_photos() :: non_neg_integer()
  def count_photos, do: Repo.aggregate(Photo, :count)

  @doc "Most recent dated photo groups, newest first, limited; photos preloaded."
  @spec recent_groups(non_neg_integer()) :: [%PhotoGroup{}]
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
  @spec image_url(String.t()) :: String.t()
  def image_url("http://" <> _ = url), do: url
  def image_url("https://" <> _ = url), do: url
  def image_url(key) when is_binary(key), do: "/media/" <> key
end
