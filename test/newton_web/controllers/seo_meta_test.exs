defmodule NewtonWeb.SeoMetaTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp published_post do
    {:ok, post} =
      Blog.create_post(%{
        slug: "seo-meta-post",
        title: "SEO Meta Post",
        body_markdown: "The excerpt paragraph.",
        published_at: ~U[2026-04-17 12:00:00Z]
      })

    post
  end

  defp meta(html, property) do
    case Regex.run(~r/<meta[^>]*property="#{property}"[^>]*content="([^"]*)"/, html) do
      [_, content] -> content
      _ -> nil
    end
  end

  defp named_meta(html, name) do
    case Regex.run(~r/<meta[^>]*name="#{name}"[^>]*content="([^"]*)"/, html) do
      [_, content] -> content
      _ -> nil
    end
  end

  test "a post page emits the full article tag set", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    assert meta(html, "og:title") == post.title
    assert meta(html, "og:description") == post.excerpt
    assert meta(html, "og:type") == "article"
    assert meta(html, "og:url") =~ "/posts/#{post.slug}"
    assert meta(html, "og:image") =~ "/og/posts/#{post.slug}"
    assert named_meta(html, "twitter:image") =~ "/og/posts/#{post.slug}"
    assert meta(html, "og:image:width") == "1200"
    assert html =~ ~r/<link rel="canonical" href="[^"]*\/posts\/#{post.slug}"/
    assert html =~ ~s(<title)
    assert html =~ post.title
  end

  test "a post page emits parseable Article JSON-LD despite the strict CSP", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    [_, json] = Regex.run(~r/<script type="application\/ld\+json"[^>]*>(.*?)<\/script>/s, html)
    decoded = Jason.decode!(json)

    article =
      if is_list(decoded), do: Enum.find(decoded, &(&1["@type"] == "Article")), else: decoded

    assert article["@type"] == "Article"
    assert article["headline"] == post.title
  end

  test "a page's SEO item only overrides what it sets, config fills the rest", %{conn: conn} do
    html = conn |> get(~p"/reading") |> html_response(200)

    assert meta(html, "og:site_name") == "James Newton"
    assert meta(html, "og:image") =~ "/og-default.png"
    assert html =~ ~r/<meta[^>]*name="twitter:card"[^>]*content="summary_large_image"/
  end

  test "a page's og:url is its own URL, item or not", %{conn: conn} do
    html = conn |> get(~p"/reading") |> html_response(200)

    assert meta(html, "og:url") =~ ~r{^http[^"]*/reading$}
  end

  test "a preview URL keeps noindex and the clean canonical", %{conn: conn} do
    {:ok, post} =
      Blog.create_post(%{slug: "preview-post", title: "Preview", body_markdown: "Draft body."})

    {:ok, post} = Blog.enable_preview(post)
    html = conn |> get(~p"/posts/#{post.slug}?p=#{post.preview_token}") |> html_response(200)

    assert html =~ ~r/<meta[^>]*name="robots"[^>]*content="noindex"/
    assert html =~ ~r/<link rel="canonical" href="[^"]*\/posts\/preview-post"/
    refute html =~ "?p="
    refute html =~ "application/ld+json"
  end

  for {path, fragment} <- [
        {"/", "Software &amp; Photography"},
        {"/photos", "Photography from"},
        {"/reading", "Books read"},
        {"/links", "elsewhere"},
        {"/resume", "work history"},
        {"/posts", "Writing"}
      ] do
    test "#{path} emits a deliberate description and canonical", %{conn: conn} do
      html = conn |> get(unquote(path)) |> html_response(200)

      description =
        Regex.run(~r/<meta[^>]*property="og:description"[^>]*content="([^"]*)"/, html)

      assert description, "no og:description on #{unquote(path)}"
      [_, content] = description
      assert content =~ ~r/#{unquote(fragment)}/i
      assert html =~ ~r/<link rel="canonical" href="[^"]*#{Regex.escape(unquote(path))}"/
    end
  end
end
