defmodule Mix.Tasks.Newton.Posts.Rerender do
  @shortdoc "Re-renders all posts' cached HTML/excerpt/reading_time from Markdown"
  use Mix.Task
  alias Newton.{Repo, Blog}
  alias Newton.Blog.Post

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Post
    |> Repo.all()
    |> Enum.each(fn post ->
      {:ok, _} = Blog.rerender_post(post)
    end)

    Mix.shell().info("Re-rendered #{Repo.aggregate(Post, :count)} posts.")
  end
end
