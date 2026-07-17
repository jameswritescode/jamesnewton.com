defmodule NewtonWeb.IndexNowNotifier do
  @moduledoc """
  Computes which public URLs a post mutation changed and submits them to
  IndexNow off the request path. Draft-only mutations submit nothing.
  """
  use NewtonWeb, :verified_routes
  require Logger

  alias Newton.Blog.Post
  alias Newton.IndexNow

  @spec notify_change(%Post{} | nil, %Post{} | nil) :: :ok
  def notify_change(before_post, after_post) do
    case changed_urls(before_post, after_post) do
      [] ->
        :ok

      urls ->
        case Task.Supervisor.start_child(Newton.TaskSupervisor, IndexNow, :submit, [urls]) do
          {:ok, _pid} -> :ok
          {:error, reason} -> Logger.warning("IndexNow task not started: #{inspect(reason)}")
        end

        :ok
    end
  end

  @spec changed_urls(%Post{} | nil, %Post{} | nil) :: [String.t()]
  def changed_urls(before_post, after_post) do
    case post_urls(before_post) ++ post_urls(after_post) do
      [] -> []
      urls -> Enum.uniq(urls) ++ [url(~p"/"), url(~p"/posts")]
    end
  end

  defp post_urls(%Post{published_at: %DateTime{}, slug: slug}), do: [url(~p"/posts/#{slug}")]
  defp post_urls(_), do: []
end
