defmodule Mix.Tasks.Newton.Posts.RerenderTest do
  use Newton.DataCase
  alias Newton.{Blog, Repo}
  alias Newton.Blog.Post

  test "re-renders all posts' body_html from body_markdown" do
    {:ok, post} = Blog.create_post(%{slug: "x", title: "X", body_markdown: "## Hi", published_at: ~U[2026-01-01 00:00:00Z]})

    Repo.update_all(Post, set: [body_html: "STALE"])
    assert Repo.get!(Post, post.id).body_html == "STALE"

    Mix.Tasks.Newton.Posts.Rerender.run([])

    assert Repo.get!(Post, post.id).body_html =~ "<h2"
  end
end
