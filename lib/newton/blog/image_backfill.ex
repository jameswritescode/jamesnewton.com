defmodule Newton.Blog.ImageBackfill do
  @moduledoc """
  One-time adoption of untracked inline post images into the post_images
  ledger. Delete this module (and its mix task) after the production run;
  ongoing drift visibility lives in `Newton.Blog.ImageAudit` and /admin/media.
  """
  import Ecto.Query
  alias Newton.Blog.{ImageAudit, Post, PostImage}
  alias Newton.Repo

  @spec run() :: %{adopted: [String.t()]}
  def run do
    tracked = ImageAudit.ledger_keys()
    photo_keys = ImageAudit.photo_keys()
    volume = ImageAudit.volume_keys()

    adopted =
      Repo.all(from p in Post, order_by: p.id)
      |> Enum.reduce([], fn post, acc -> adopt_post(post, tracked, photo_keys, volume, acc) end)

    %{adopted: Enum.reverse(adopted)}
  end

  defp adopt_post(post, tracked, photo_keys, volume, adopted) do
    post.body_markdown
    |> ImageAudit.extract_keys()
    |> Enum.reduce(adopted, fn key, acc ->
      cond do
        MapSet.member?(tracked, key) or MapSet.member?(photo_keys, key) or key in acc ->
          acc

        MapSet.member?(volume, key) ->
          {:ok, _} =
            %PostImage{post_id: post.id}
            |> PostImage.create_changeset(%{key: key})
            |> Repo.insert()

          [key | acc]

        true ->
          acc
      end
    end)
  end
end
