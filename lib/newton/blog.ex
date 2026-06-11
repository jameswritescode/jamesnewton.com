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

  def list_posts, do: Repo.all(from p in Post, order_by: [desc: p.published_at])

  @doc "Fetch any post by id (admin), regardless of publish status."
  def get_post!(id), do: Repo.get!(Post, id)

  @doc "Fetch any post by slug (admin), regardless of publish status."
  def get_post_by_slug!(slug), do: Repo.get_by!(Post, slug: slug)

  @doc "Delete a post."
  def delete_post(%Post{} = post), do: Repo.delete(post)

  @doc "Build a post changeset for forms."
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

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
