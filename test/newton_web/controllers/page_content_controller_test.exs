defmodule NewtonWeb.PageContentControllerTest do
  use NewtonWeb.ConnCase, async: true
  import Newton.AccountsFixtures

  test "renders a published page at /:slug", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "about",
        title: "About Me",
        body_markdown: "Hi there.",
        published: true
      })

    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About Me"
    assert html_response(conn, 200) =~ "Hi there."
  end

  test "a draft 404s for an anonymous visitor", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "secret",
        title: "Secret",
        body_markdown: "shh",
        published: false
      })

    assert_error_sent 404, fn -> get(conn, ~p"/secret") end
  end

  test "a draft renders with a banner for a logged-in admin", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "secret",
        title: "Secret Draft",
        body_markdown: "shh",
        published: false
      })

    conn = conn |> log_in_user(user_fixture()) |> get(~p"/secret")
    assert html_response(conn, 200) =~ "Secret Draft"
    assert html_response(conn, 200) =~ "Draft"
  end

  test "a page without a meta description falls back to its body", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "colophon",
        title: "Colophon",
        body_markdown: "Built with Phoenix and a lot of coffee.",
        published: true
      })

    html = conn |> get(~p"/colophon") |> html_response(200)

    assert [_, description] =
             Regex.run(~r/<meta[^>]*name="description"[^>]*content="([^"]*)"/, html)

    assert description == "Built with Phoenix and a lot of coffee."
  end

  test "a page's own meta description wins over the body fallback", %{conn: conn} do
    {:ok, _} =
      Newton.Pages.create_page(%{
        slug: "colophon",
        title: "Colophon",
        body_markdown: "Built with Phoenix and a lot of coffee.",
        meta_description: "How this site is put together.",
        published: true
      })

    html = conn |> get(~p"/colophon") |> html_response(200)

    assert [_, description] =
             Regex.run(~r/<meta[^>]*name="description"[^>]*content="([^"]*)"/, html)

    assert description == "How this site is put together."
  end

  test "an unknown slug 404s", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/nope-nope") end
  end
end
