defmodule NewtonWeb.SEOTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        slug: "seo-post-#{System.unique_integer([:positive])}",
        title: "SEO Post",
        body_markdown: "First paragraph as excerpt.",
        published_at: ~U[2026-04-17 12:00:00Z]
      })
      |> Blog.create_post()

    post
  end

  test "a published post builds article open graph with the live card image", %{conn: conn} do
    post = post_fixture()
    og = SEO.OpenGraph.Build.build(post, conn)

    assert og.title == post.title
    assert og.description == post.excerpt
    assert %SEO.OpenGraph.Article{} = og.detail
    assert og.detail.published_time
    assert og.url =~ "/posts/#{post.slug}"
    assert og.image.url =~ "/og/posts/#{post.slug}"
    assert og.image.width == 1200
    assert og.image.height == 630
    assert og.image.alt == post.title
  end

  test "an unpublished post falls back to the static default card", %{conn: conn} do
    post = post_fixture(%{published_at: nil, slug: "seo-draft"})
    og = SEO.OpenGraph.Build.build(post, conn)

    assert og.image.url =~ "/og-default.png"
  end

  test "a post's twitter card carries the same image as its open graph", %{conn: conn} do
    published = post_fixture()
    assert SEO.Twitter.Build.build(published, conn).image =~ "/og/posts/#{published.slug}"

    draft = post_fixture(%{published_at: nil, slug: "twitter-draft"})
    assert SEO.Twitter.Build.build(draft, conn).image =~ "/og-default.png"
  end

  test "a post's site build carries the clean canonical", %{conn: conn} do
    post = post_fixture()
    site = SEO.Site.Build.build(post, conn)

    assert site.canonical_url =~ "/posts/#{post.slug}"
    assert site.title == post.title
  end

  test "a post's JSON-LD is an Article with an embedded Person author", %{conn: conn} do
    post = post_fixture()
    [article] = List.wrap(SEO.JSONLD.Build.build(post, conn))

    assert article["@type"] == "Article"
    assert article["headline"] == post.title
    assert article["author"]["name"] == "James Newton"
    assert article["image"] =~ "/og/posts/#{post.slug}"
  end

  test "an unpublished post emits no JSON-LD", %{conn: conn} do
    post = post_fixture(%{published_at: nil, slug: "jsonld-draft"})

    assert SEO.JSONLD.Build.build(post, conn) == nil
  end

  test "a Page item builds titled, self-canonical tags", %{conn: conn} do
    page = %NewtonWeb.SEO.Page{
      title: "Photos",
      description: "Photography from hikes and travels.",
      path: "/photos"
    }

    og = SEO.OpenGraph.Build.build(page, conn)
    site = SEO.Site.Build.build(page, conn)

    assert og.title == "Photos"
    assert og.description == "Photography from hikes and travels."
    assert site.canonical_url =~ "/photos"
  end

  test "the home Page emits WebSite and Person JSON-LD", %{conn: conn} do
    page = %NewtonWeb.SEO.Page{title: "James Newton", description: "d", path: "/"}
    types = page |> SEO.JSONLD.Build.build(conn) |> List.wrap() |> Enum.map(& &1["@type"])
    assert "WebSite" in types
    assert "Person" in types
  end
end
