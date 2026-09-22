defmodule Newton.Blog.ImageAudit do
  @moduledoc """
  Read-only audit of the media volume against its owners (gallery photos, the
  post- and page-image ledgers, and post and page bodies), plus guarded deletion
  of true strays. Never touches owned or referenced files.
  """
  import Ecto.Query
  alias Newton.Blog.{Post, PostImage}
  alias Newton.Gallery.Photo
  alias Newton.Pages.{Page, PageImage}
  alias Newton.Storage
  alias Newton.Repo

  @media_url ~r{/media/([A-Za-z0-9_-]+\.[A-Za-z0-9]+)}

  @spec run() :: %{missing: [{String.t(), String.t()}], strays: [String.t()]}
  def run do
    bodies = post_bodies() ++ page_bodies()
    volume = volume_keys()
    referenced = MapSet.new(Enum.flat_map(bodies, fn {_slug, body} -> extract_keys(body) end))
    owned = MapSet.union(ledger_keys(), photo_keys())

    missing =
      for {slug, body} <- bodies,
          key <- extract_keys(body),
          not MapSet.member?(volume, key),
          do: {slug, key}

    strays =
      volume
      |> MapSet.difference(owned)
      |> MapSet.difference(referenced)
      |> Enum.sort()

    %{missing: missing, strays: strays}
  end

  @spec stray?(String.t()) :: boolean()
  def stray?(key) do
    key in run().strays
  end

  @spec delete_stray(String.t()) :: :ok | {:error, :not_stray}
  def delete_stray(key) do
    if stray?(key) do
      Storage.delete(key)
    else
      {:error, :not_stray}
    end
  end

  @spec extract_keys(String.t() | nil) :: [String.t()]
  def extract_keys(body) do
    @media_url
    |> Regex.scan(body || "")
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.uniq()
  end

  @spec ledger_keys() :: MapSet.t(String.t())
  def ledger_keys do
    post_keys = Repo.all(from i in PostImage, select: i.key)
    page_keys = Repo.all(from i in PageImage, select: i.key)
    MapSet.new(post_keys ++ page_keys)
  end

  @spec post_bodies() :: [{String.t(), String.t() | nil}]
  def post_bodies do
    Repo.all(from p in Post, order_by: p.id, select: {p.slug, p.body_markdown})
  end

  @spec page_bodies() :: [{String.t(), String.t() | nil}]
  def page_bodies do
    Repo.all(from p in Page, order_by: p.id, select: {p.slug, p.body_markdown})
  end

  @spec photo_keys() :: MapSet.t(String.t())
  def photo_keys do
    Repo.all(from p in Photo, select: {p.image_key, p.thumb_key})
    |> Enum.flat_map(fn {a, b} -> [a, b] end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @spec volume_keys() :: MapSet.t(String.t())
  def volume_keys do
    root = Application.fetch_env!(:newton, :media_root)

    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.filter(&File.regular?(Path.join(root, &1)))
        |> MapSet.new()

      {:error, _} ->
        MapSet.new()
    end
  end
end
