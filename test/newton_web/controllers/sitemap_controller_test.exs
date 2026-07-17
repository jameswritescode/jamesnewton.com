defmodule NewtonWeb.SitemapControllerTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  describe "GET /sitemap.xml" do
    test "lists published posts with date-only lastmod plus the static pages", %{conn: conn} do
      {:ok, post} =
        Blog.create_post(%{
          slug: "sitemap-post",
          title: "Sitemap Post",
          body_markdown: "Hello.",
          published_at: DateTime.utc_now()
        })

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert response_content_type(conn, :xml) =~ "application/xml"
      assert body =~ "<loc>#{url(~p"/posts/sitemap-post")}</loc>"

      assert body =~
               "<lastmod>#{post.updated_at |> DateTime.to_date() |> Date.to_iso8601()}</lastmod>"

      for path <- ["/", "/posts", "/reading", "/photos", "/links", "/resume"] do
        assert body =~ "<loc>#{NewtonWeb.Endpoint.url() <> path}</loc>"
      end
    end

    test "drafts do not appear", %{conn: conn} do
      {:ok, _draft} =
        Blog.create_post(%{slug: "secret-draft", title: "Draft", body_markdown: "Shh."})

      body = conn |> get(~p"/sitemap.xml") |> response(200)

      refute body =~ "secret-draft"
      refute body =~ "<lastmod>"
    end
  end

  describe "GET /robots.txt" do
    test "allows all crawlers and points at the sitemap", %{conn: conn} do
      conn = get(conn, ~p"/robots.txt")
      body = response(conn, 200)

      assert response_content_type(conn, :text) =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ "Sitemap: #{url(~p"/sitemap.xml")}"
    end
  end
end
