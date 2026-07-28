defmodule Newton.BlogTest do
  use Newton.DataCase
  alias Newton.{Blog, Repo}
  alias Newton.Blog.Post

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

  test "create_post requires slug and title" do
    {:error, changeset} = Blog.create_post(%{})
    assert %{slug: _, title: _} = errors_on(changeset)
  end

  test "a post can be created without a body" do
    assert {:ok, post} = Blog.create_post(%{title: "Empty", slug: "empty", body_markdown: ""})
    assert post.body_markdown == ""
  end

  test "next_untitled_slug returns the first free untitled slug" do
    assert Blog.next_untitled_slug() == "untitled-post"

    {:ok, _} =
      Blog.create_post(%{title: "Untitled post", slug: "untitled-post", body_markdown: ""})

    assert Blog.next_untitled_slug() == "untitled-post-2"

    {:ok, _} =
      Blog.create_post(%{title: "Untitled post", slug: "untitled-post-2", body_markdown: ""})

    assert Blog.next_untitled_slug() == "untitled-post-3"
  end

  test "list_posts/1 filters by status and sorts newest-first across drafts and published" do
    {:ok, _pub_old} =
      Blog.create_post(%{@valid | slug: "pub-old", published_at: ~U[2026-01-01 00:00:00Z]})

    {:ok, _pub_new} =
      Blog.create_post(%{@valid | slug: "pub-new", published_at: ~U[2026-03-01 00:00:00Z]})

    {:ok, draft} = Blog.create_post(%{@valid | slug: "a-draft", published_at: nil})

    all = Blog.list_posts(:all) |> Enum.map(& &1.slug)
    assert all == ["a-draft", "pub-new", "pub-old"]

    assert Blog.list_posts(:drafts) |> Enum.map(& &1.slug) == ["a-draft"]
    assert Blog.list_posts(:published) |> Enum.map(& &1.slug) == ["pub-new", "pub-old"]
    assert Blog.list_posts() |> Enum.map(& &1.id) |> Enum.member?(draft.id)
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

  test "count_posts/0 counts all; count_drafts/0 counts those without published_at" do
    {:ok, _} = Blog.create_post(@valid)
    {:ok, _} = Blog.create_post(%{@valid | slug: "draft", published_at: nil})

    assert Blog.count_posts() == 2
    assert Blog.count_drafts() == 1
  end

  test "get_post!/1 fetches any post by id, including drafts" do
    {:ok, draft} = Blog.create_post(%{@valid | slug: "d", published_at: nil})
    assert Blog.get_post!(draft.id).id == draft.id
  end

  test "get_post_by_slug!/1 fetches any post by slug, including drafts" do
    {:ok, draft} = Blog.create_post(%{@valid | slug: "draft-slug", published_at: nil})
    assert Blog.get_post_by_slug!("draft-slug").id == draft.id
    assert_raise Ecto.NoResultsError, fn -> Blog.get_post_by_slug!("missing") end
  end

  test "delete_post/1 removes the post" do
    {:ok, post} = Blog.create_post(@valid)
    {:ok, _} = Blog.delete_post(post)
    assert_raise Ecto.NoResultsError, fn -> Blog.get_post!(post.id) end
  end

  test "change_post/2 returns a changeset" do
    {:ok, post} = Blog.create_post(@valid)
    assert %Ecto.Changeset{} = Blog.change_post(post, %{title: "New"})
  end

  test "publish_status/1 derives draft/scheduled/published from a datetime" do
    future = DateTime.add(DateTime.utc_now(), 60, :minute)
    past = DateTime.add(DateTime.utc_now(), -60, :minute)
    assert Blog.publish_status(nil) == :draft
    assert Blog.publish_status(future) == :scheduled
    assert Blog.publish_status(past) == :published
  end

  describe "draft preview tokens" do
    test "enable_preview mints a token on a draft; disable clears it" do
      {:ok, draft} = Blog.create_post(%{slug: "d1", title: "D1", body_markdown: "x"})
      assert is_nil(draft.preview_token)

      {:ok, shared} = Blog.enable_preview(draft)
      assert is_binary(shared.preview_token)
      assert byte_size(shared.preview_token) >= 32

      {:ok, off} = Blog.disable_preview(shared)
      assert is_nil(off.preview_token)
    end

    test "enable_preview is a no-op on a published post" do
      {:ok, post} =
        Blog.create_post(%{
          slug: "p1",
          title: "P1",
          body_markdown: "x",
          published_at: ~U[2026-01-01 00:00:00Z]
        })

      {:ok, post} = Blog.enable_preview(post)
      assert is_nil(post.preview_token)
    end

    test "publishing a shared draft clears its token" do
      {:ok, draft} = Blog.create_post(%{slug: "d2", title: "D2", body_markdown: "x"})
      {:ok, shared} = Blog.enable_preview(draft)
      assert shared.preview_token

      {:ok, published} = Blog.update_post(shared, %{"published_at" => ~U[2026-01-01 00:00:00Z]})
      assert is_nil(published.preview_token)
    end

    test "get_post_by_preview_token returns the post only for the right token" do
      {:ok, draft} = Blog.create_post(%{slug: "d3", title: "D3", body_markdown: "x"})
      {:ok, shared} = Blog.enable_preview(draft)

      assert %{id: id} = Blog.get_post_by_preview_token("d3", shared.preview_token)
      assert id == shared.id
      assert is_nil(Blog.get_post_by_preview_token("d3", "wrong-token"))
      assert is_nil(Blog.get_post_by_preview_token("d3", ""))
    end
  end

  describe "update_post/2 optimistic locking" do
    test "returns {:error, :stale} and keeps the newer content when the post changed underneath" do
      {:ok, post} =
        Blog.create_post(%{"title" => "Race", "slug" => "race", "body_markdown" => "original"})

      {:ok, _newer} = Blog.update_post(post, %{"body_markdown" => "from computer A"})

      assert {:error, :stale} =
               Blog.update_post(post, %{"body_markdown" => "stale from computer B"})

      assert Repo.get!(Post, post.id).body_markdown == "from computer A"
    end

    test "sequential updates through fresh structs succeed" do
      {:ok, post} =
        Blog.create_post(%{"title" => "Seq", "slug" => "seq", "body_markdown" => "one"})

      {:ok, post} = Blog.update_post(post, %{"body_markdown" => "two"})

      assert {:ok, %Post{body_markdown: "three"}} =
               Blog.update_post(post, %{"body_markdown" => "three"})
    end
  end
end
