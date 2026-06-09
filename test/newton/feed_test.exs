defmodule Newton.FeedTest do
  use Newton.DataCase
  alias Newton.{Blog, Feed, Gallery, Reading}

  test "recent/1 merges posts, reading, and photo groups newest-first" do
    {:ok, _post} =
      Blog.create_post(%{
        slug: "p",
        title: "Post",
        body_markdown: "Body.",
        published_at: ~U[2026-04-17 00:00:00Z]
      })

    {:ok, _book} =
      Reading.create_entry(%{
        title: "Book",
        author: "A",
        status: :read,
        finished_at: ~D[2026-04-18]
      })

    {:ok, g} = Gallery.create_group(%{slug: "sierra", title: "Sierra", taken_on: ~D[2026-04-16]})

    {:ok, _} =
      Gallery.add_photo(g, %{image_key: "https://example.com/a.jpg", alt: "A", position: 1})

    kinds = Feed.recent(10) |> Enum.map(& &1.kind)
    assert kinds == [:book, :post, :photo]
  end

  test "recent/1 excludes unpublished posts" do
    {:ok, _draft} =
      Blog.create_post(%{slug: "d", title: "Draft", body_markdown: "B.", published_at: nil})

    assert Feed.recent(10) == []
  end

  test "recent/1 caps the number of items at the limit" do
    for i <- 1..5 do
      {:ok, _} =
        Blog.create_post(%{
          slug: "p#{i}",
          title: "P#{i}",
          body_markdown: "B.",
          published_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :day)
        })
    end

    assert length(Feed.recent(3)) == 3
  end
end
