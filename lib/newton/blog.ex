defmodule Newton.Blog do
  @moduledoc "The blog context: posts and their queries."
  import Ecto.Query, warn: false
  alias Newton.Blog.Post
  alias Newton.Blog.PostImage
  alias Newton.Gallery.Storage
  alias Newton.Repo

  # Fields needed to render post lists and the home feed — everything except the
  # large body_markdown/body_html text columns, which only the show page loads.
  @summary_fields [
    :id,
    :slug,
    :title,
    :excerpt,
    :reading_time,
    :published_at,
    :inserted_at,
    :updated_at
  ]

  @spec create_post(map()) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def create_post(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert()
  end

  @spec update_post(%Post{}, map()) ::
          {:ok, %Post{}} | {:error, Ecto.Changeset.t() | :stale}
  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @spec rerender_post(%Post{}) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def rerender_post(%Post{} = post) do
    post |> Post.rerender_changeset() |> Repo.update()
  end

  @doc """
  Published posts, newest first, as lightweight summaries (no body columns).
  Pass a limit to fetch only the most recent N (used by the home feed).
  """
  @spec list_published_posts(non_neg_integer() | nil) :: [%Post{}]
  def list_published_posts(limit \\ nil) do
    from(p in published_query(), select: struct(p, @summary_fields))
    |> maybe_limit(limit)
    |> Repo.all()
  end

  @spec get_published_post!(String.t()) :: %Post{}
  def get_published_post!(slug) do
    Repo.one!(from p in published_query(), where: p.slug == ^slug)
  end

  @doc "Admin post list, optionally filtered by status, newest-first."
  @spec list_posts(:all | :drafts | :published) :: [%Post{}]
  def list_posts(filter \\ :all) do
    from(p in Post, order_by: [desc: coalesce(p.published_at, p.inserted_at)])
    |> filter_posts(filter)
    |> Repo.all()
  end

  defp filter_posts(query, :drafts), do: from(p in query, where: is_nil(p.published_at))
  defp filter_posts(query, :published), do: from(p in query, where: not is_nil(p.published_at))
  defp filter_posts(query, _all), do: query

  @doc "Fetch any post by id (admin), regardless of publish status."
  @spec get_post!(integer()) :: %Post{}
  def get_post!(id), do: Repo.get!(Post, id)

  @doc "Fetch any post by id (admin), returning nil if it doesn't exist."
  @spec get_post(term()) :: %Post{} | nil
  def get_post(id), do: Repo.get(Post, id)

  @doc "Fetch any post by slug (admin), regardless of publish status."
  @spec get_post_by_slug!(String.t()) :: %Post{}
  def get_post_by_slug!(slug), do: Repo.get_by!(Post, slug: slug)

  @doc "Mint a preview token for a draft (idempotent). No-op once published."
  @spec enable_preview(%Post{}) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def enable_preview(%Post{published_at: nil} = post) do
    token =
      post.preview_token || 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    post |> Ecto.Changeset.change(preview_token: token) |> Repo.update()
  end

  def enable_preview(%Post{} = post), do: {:ok, post}

  @doc "Clear a post's preview token, invalidating any shared link."
  @spec disable_preview(%Post{}) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def disable_preview(%Post{} = post) do
    post |> Ecto.Changeset.change(preview_token: nil) |> Repo.update()
  end

  @doc "Fetch a post by slug only if `token` matches its preview token (constant-time)."
  @spec get_post_by_preview_token(String.t(), String.t()) :: %Post{} | nil
  def get_post_by_preview_token(slug, token) when is_binary(token) do
    case Repo.get_by(Post, slug: slug) do
      %Post{preview_token: stored} = post when is_binary(stored) ->
        if Plug.Crypto.secure_compare(token, stored), do: post, else: nil

      _ ->
        nil
    end
  end

  @doc "Deletes an image's file and ledger row. Refused while the post still uses it."
  @spec delete_image(%PostImage{}) ::
          {:ok, %PostImage{}} | {:error, :referenced | Ecto.Changeset.t()}
  def delete_image(%PostImage{} = image) do
    post = Repo.get!(Post, image.post_id)

    if image_referenced?(post, image) do
      {:error, :referenced}
    else
      Storage.delete(image.key)
      Repo.delete(image)
    end
  end

  @doc "Deletes a post and the image files it owns; ledger rows cascade."
  @spec delete_post(%Post{}) :: {:ok, %Post{}} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post) do
    post |> list_images() |> Enum.each(&Storage.delete(&1.key))
    Repo.delete(post)
  end

  @doc "Build a post changeset for forms."
  @spec change_post(%Post{}, map()) :: Ecto.Changeset.t()
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc "First free slug in the series untitled-post, untitled-post-2, …"
  @spec next_untitled_slug() :: String.t()
  def next_untitled_slug do
    taken =
      Repo.all(from p in Post, where: like(p.slug, "untitled-post%"), select: p.slug)
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn n ->
      slug = if n == 1, do: "untitled-post", else: "untitled-post-#{n}"
      if slug not in taken, do: slug
    end)
  end

  @doc "Derive publish status from a `published_at` value (or nil)."
  @spec publish_status(DateTime.t() | nil) :: :draft | :scheduled | :published
  def publish_status(nil), do: :draft

  def publish_status(%DateTime{} = at) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt, do: :scheduled, else: :published
  end

  @doc "Total number of posts."
  @spec count_posts() :: non_neg_integer()
  def count_posts, do: Repo.aggregate(Post, :count)

  @doc "Number of draft posts (no publish date set)."
  @spec count_drafts() :: non_neg_integer()
  def count_drafts do
    Repo.aggregate(from(p in Post, where: is_nil(p.published_at)), :count)
  end

  defp published_query do
    now = DateTime.utc_now()

    from p in Post,
      where: not is_nil(p.published_at) and p.published_at <= ^now,
      order_by: [desc: p.published_at]
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n), do: from(q in query, limit: ^n)

  @doc "Records an editor upload on the post's image ledger."
  @spec attach_image(%Post{}, String.t(), String.t() | nil) ::
          {:ok, %PostImage{}} | {:error, Ecto.Changeset.t()}
  def attach_image(%Post{} = post, key, original_filename \\ nil) do
    %PostImage{post_id: post.id}
    |> PostImage.create_changeset(%{key: key, original_filename: original_filename})
    |> Repo.insert()
  end

  @spec list_images(%Post{}) :: [%PostImage{}]
  def list_images(%Post{} = post) do
    Repo.all(
      from i in PostImage,
        where: i.post_id == ^post.id,
        order_by: [asc: i.inserted_at, asc: i.id]
    )
  end

  @doc "Whether the post's markdown still uses the image. Usage is derived, never stored."
  @spec image_referenced?(%Post{}, %PostImage{}) :: boolean()
  def image_referenced?(%Post{} = post, %PostImage{} = image) do
    String.contains?(post.body_markdown || "", image.key)
  end
end
