defmodule NewtonWeb.PageContentController do
  use NewtonWeb, :controller
  alias Newton.Markdown
  alias Newton.Pages
  alias Newton.Pages.Page

  def show(conn, %{"slug" => slug}) do
    render_page(conn, Pages.get_page_by_slug(slug), admin?(conn))
  end

  defp render_page(conn, %Page{published: true} = page, _admin) do
    deliver(conn, page, false)
  end

  defp render_page(conn, %Page{published: false} = page, true) do
    conn |> assign(:page_robots, "noindex") |> deliver(page, true)
  end

  defp render_page(_conn, _page, _admin), do: raise(Ecto.NoResultsError, queryable: Page)

  defp deliver(conn, %Page{} = page, preview?) do
    conn
    |> SEO.assign(%NewtonWeb.SEO.Page{
      title: page.title,
      description: description(page),
      path: "/#{page.slug}"
    })
    |> render(:show, page_title: page.title, page: page, preview: preview?)
  end

  defp description(%Page{meta_description: meta}) when is_binary(meta) and meta != "", do: meta
  defp description(%Page{body_markdown: body}), do: Markdown.excerpt(body || "")

  defp admin?(conn), do: match?(%{user: %{}}, conn.assigns[:current_scope])
end
