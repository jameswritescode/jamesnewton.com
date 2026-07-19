defmodule NewtonWeb.PublicationNotifier do
  @moduledoc """
  Fans a post mutation out to every syndication target: IndexNow (changed
  URLs) and standard.site (document records). Draft-only mutations notify
  nothing. Each target runs in its own supervised task so one failing
  integration cannot starve another.
  """
  use NewtonWeb, :verified_routes
  require Logger

  alias Newton.Blog.Post
  alias Newton.IndexNow
  alias Newton.Standard

  @spec notify_change(%Post{} | nil, %Post{} | nil) :: :ok
  def notify_change(before_post, after_post) do
    case changed_urls(before_post, after_post) do
      [] -> :ok
      urls -> start_task(IndexNow, :submit, [urls], "IndexNow")
    end

    for {fun, arg} <- standard_ops(before_post, after_post) do
      start_task(Standard, fun, [arg], "standard.site")
    end

    :ok
  end

  @spec changed_urls(%Post{} | nil, %Post{} | nil) :: [String.t()]
  def changed_urls(before_post, after_post) do
    case post_urls(before_post) ++ post_urls(after_post) do
      [] -> []
      urls -> Enum.uniq(urls) ++ [url(~p"/"), url(~p"/posts")]
    end
  end

  @spec standard_ops(%Post{} | nil, %Post{} | nil) ::
          [{:put_document, %Post{}} | {:delete_document, String.t()}]
  def standard_ops(before_post, after_post) do
    case {published(before_post), published(after_post)} do
      {nil, nil} -> []
      {nil, post} -> [{:put_document, post}]
      {post, nil} -> [{:delete_document, post.slug}]
      {%Post{slug: slug}, %Post{slug: slug} = post} -> [{:put_document, post}]
      {old, post} -> [{:delete_document, old.slug}, {:put_document, post}]
    end
  end

  defp published(%Post{published_at: %DateTime{}} = post), do: post
  defp published(_), do: nil

  defp post_urls(%Post{published_at: %DateTime{}, slug: slug}), do: [url(~p"/posts/#{slug}")]
  defp post_urls(_), do: []

  defp start_task(mod, fun, args, label) do
    case Task.Supervisor.start_child(Newton.TaskSupervisor, mod, fun, args) do
      {:ok, _pid} -> :ok
      {:error, reason} -> Logger.warning("#{label} task not started: #{inspect(reason)}")
    end
  end
end
