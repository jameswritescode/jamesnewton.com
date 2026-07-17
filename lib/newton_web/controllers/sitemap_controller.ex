defmodule NewtonWeb.SitemapController do
  @moduledoc "Serves sitemap.xml and robots.txt for crawlers."
  use NewtonWeb, :controller

  alias Newton.Blog

  @cache_control "public, max-age=3600"

  def sitemap(conn, _params) do
    xml =
      :urlset
      |> XmlBuilder.document(
        %{xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9"},
        static_entries() ++ post_entries()
      )
      |> XmlBuilder.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", @cache_control)
    |> send_resp(200, xml)
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", @cache_control)
    |> send_resp(200, """
    User-agent: *
    Disallow:

    Sitemap: #{url(~p"/sitemap.xml")}
    """)
  end

  defp static_entries do
    [
      url(~p"/"),
      url(~p"/posts"),
      url(~p"/reading"),
      url(~p"/photos"),
      url(~p"/links"),
      url(~p"/resume")
    ]
    |> Enum.map(&{:url, nil, [{:loc, nil, &1}]})
  end

  defp post_entries do
    for post <- Blog.list_published_posts() do
      {:url, nil,
       [
         {:loc, nil, url(~p"/posts/#{post.slug}")},
         {:lastmod, nil, post.updated_at |> DateTime.to_date() |> Date.to_iso8601()}
       ]}
    end
  end
end
