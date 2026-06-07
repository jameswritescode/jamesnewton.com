defmodule Newton.Blog do
  @moduledoc "The blog context: posts and their queries."
  import Ecto.Query, warn: false
  alias Newton.Repo
  alias Newton.Blog.Post

  def create_post(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert()
  end

  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  end

  def list_published_posts do
    Repo.all(published_query())
  end

  def get_published_post!(slug) do
    Repo.one!(from p in published_query(), where: p.slug == ^slug)
  end

  def list_posts, do: Repo.all(from p in Post, order_by: [desc: p.published_at])

  defp published_query do
    now = DateTime.utc_now()

    from p in Post,
      where: not is_nil(p.published_at) and p.published_at <= ^now,
      order_by: [desc: p.published_at]
  end
end
