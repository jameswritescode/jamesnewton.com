defmodule Newton.BlogTest do
  use Newton.DataCase
  alias Newton.Blog

  @valid %{
    slug: "hello-world",
    title: "Hello World",
    body_markdown: "First paragraph here.\n\n## Heading\n\nMore text.",
    published_at: ~U[2026-01-01 00:00:00Z]
  }

  test "create_post renders body_html, derives excerpt and reading_time" do
    {:ok, post} = Blog.create_post(@valid)
    assert post.body_html =~ "<h2"
    assert post.excerpt =~ "First paragraph here"
    assert post.reading_time >= 1
  end

  test "create_post keeps an explicit excerpt" do
    {:ok, post} = Blog.create_post(Map.put(@valid, :excerpt, "Custom excerpt"))
    assert post.excerpt == "Custom excerpt"
  end

  test "create_post requires slug, title, body_markdown" do
    {:error, changeset} = Blog.create_post(%{})
    assert %{slug: _, title: _, body_markdown: _} = errors_on(changeset)
  end

  test "slug must be unique" do
    {:ok, _} = Blog.create_post(@valid)
    {:error, changeset} = Blog.create_post(@valid)
    assert "has already been taken" in errors_on(changeset).slug
  end

  test "list_published_posts returns only past, published posts newest-first" do
    {:ok, _draft} = Blog.create_post(%{@valid | slug: "draft", published_at: nil})

    {:ok, _future} =
      Blog.create_post(%{@valid | slug: "future", published_at: ~U[2999-01-01 00:00:00Z]})

    {:ok, _older} =
      Blog.create_post(%{@valid | slug: "older", published_at: ~U[2026-01-01 00:00:00Z]})

    {:ok, _newer} =
      Blog.create_post(%{@valid | slug: "newer", published_at: ~U[2026-02-01 00:00:00Z]})

    slugs = Blog.list_published_posts() |> Enum.map(& &1.slug)
    assert slugs == ["newer", "older"]
  end

  test "get_published_post!/1 fetches by slug and raises on miss" do
    {:ok, post} = Blog.create_post(@valid)
    assert Blog.get_published_post!("hello-world").id == post.id
    assert_raise Ecto.NoResultsError, fn -> Blog.get_published_post!("nope") end
  end

  test "list_published_posts/0 returns summaries without the body columns" do
    {:ok, _} = Blog.create_post(@valid)
    [post] = Blog.list_published_posts()

    assert post.title == "Hello World"
    assert is_nil(post.body_html)
    assert is_nil(post.body_markdown)
  end

  test "list_published_posts/1 returns only the most recent N" do
    for i <- 1..3 do
      {:ok, _} =
        Blog.create_post(%{
          @valid
          | slug: "p#{i}",
            published_at: DateTime.add(~U[2026-01-01 00:00:00Z], i, :day)
        })
    end

    posts = Blog.list_published_posts(2)
    assert Enum.map(posts, & &1.slug) == ["p3", "p2"]
  end
end
