defmodule NewtonWeb.OgImageControllerTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog

  defp publish!(slug, title) do
    {:ok, post} =
      Blog.create_post(%{
        slug: slug,
        title: title,
        body_markdown: "Some body text for the excerpt.",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    post
  end

  test "renders a 1200x630 PNG card for a published post", %{conn: conn} do
    publish!("og-endpoint", "Endpoint Card")

    conn = get(conn, ~p"/og/posts/og-endpoint")

    assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    body = response(conn, 200)
    assert <<0x89, "PNG", _::binary>> = body

    {:ok, img} = Image.from_binary(body)
    assert {Image.width(img), Image.height(img)} == {1200, 630}
  end

  test "sets a public cache-control header", %{conn: conn} do
    publish!("og-cache", "Cache Me")

    conn = get(conn, ~p"/og/posts/og-cache")

    assert ["public" <> _] = get_resp_header(conn, "cache-control")
  end

  test "404s for an unknown or unpublished slug", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/og/posts/does-not-exist") end
  end
end
