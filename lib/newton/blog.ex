defmodule Newton.Blog do
  @moduledoc "The blog context: posts and their queries."
  import Ecto.Query, warn: false
  alias Newton.Blog.Post
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

  def create_post(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert()
  end

  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  end

  def rerender_post(%Post{} = post) do
    post |> Post.rerender_changeset() |> Repo.update()
  end

  @doc """
  Published posts, newest first, as lightweight summaries (no body columns).
  Pass a limit to fetch only the most recent N (used by the home feed).
  """
  def list_published_posts(limit \\ nil) do
    from(p in published_query(), select: struct(p, @summary_fields))
    |> maybe_limit(limit)
    |> Repo.all()
  end

  def get_published_post!(slug) do
    Repo.one!(from p in published_query(), where: p.slug == ^slug)
  end

  @doc "Admin post list, optionally filtered by status, newest-first."
  def list_posts(filter \\ :all) do
    from(p in Post, order_by: [desc: coalesce(p.published_at, p.inserted_at)])
    |> filter_posts(filter)
    |> Repo.all()
  end

  defp filter_posts(query, :drafts), do: from(p in query, where: is_nil(p.published_at))
  defp filter_posts(query, :published), do: from(p in query, where: not is_nil(p.published_at))
  defp filter_posts(query, _all), do: query

  @doc "Fetch any post by id (admin), regardless of publish status."
  def get_post!(id), do: Repo.get!(Post, id)

  @doc "Fetch any post by slug (admin), regardless of publish status."
  def get_post_by_slug!(slug), do: Repo.get_by!(Post, slug: slug)

  @doc "Mint a preview token for a draft (idempotent). No-op once published."
  def enable_preview(%Post{published_at: nil} = post) do
    token =
      post.preview_token || 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    post |> Ecto.Changeset.change(preview_token: token) |> Repo.update()
  end

  def enable_preview(%Post{} = post), do: {:ok, post}

  @doc "Clear a post's preview token, invalidating any shared link."
  def disable_preview(%Post{} = post) do
    post |> Ecto.Changeset.change(preview_token: nil) |> Repo.update()
  end

  @doc "Fetch a post by slug only if `token` matches its preview token (constant-time)."
  def get_post_by_preview_token(slug, token) when is_binary(token) do
    case Repo.get_by(Post, slug: slug) do
      %Post{preview_token: stored} = post when is_binary(stored) ->
        if Plug.Crypto.secure_compare(token, stored), do: post, else: nil

      _ ->
        nil
    end
  end

  @doc "Delete a post."
  def delete_post(%Post{} = post), do: Repo.delete(post)

  @doc "Build a post changeset for forms."
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc "First free slug in the series untitled-post, untitled-post-2, …"
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
  def publish_status(nil), do: :draft

  def publish_status(%DateTime{} = at) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt, do: :scheduled, else: :published
  end

  @doc "Total number of posts."
  def count_posts, do: Repo.aggregate(Post, :count)

  @doc "Number of draft posts (no publish date set)."
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
end
