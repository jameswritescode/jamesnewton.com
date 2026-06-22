defmodule NewtonWeb.PostController do
  use NewtonWeb, :controller
  alias Newton.Blog
  alias Newton.Blog.Post

  def index(conn, _params) do
    render(conn, :index, page_title: "Posts", posts: Blog.list_published_posts())
  end

  def show(conn, %{"slug" => slug} = params) do
    case fetch_post(conn.assigns.current_scope, slug, params["p"]) do
      {:preview, post} ->
        conn
        |> assign(:page_robots, "noindex")
        |> put_og(post)
        |> render(:show, page_title: post.title, post: post, preview: true)

      post ->
        conn
        |> put_og(post)
        |> render(:show, page_title: post.title, post: post, preview: false)
    end
  end

  # Published posts point og:image at their live, on-demand card; drafts/previews
  # (noindex, and the on-demand endpoint only serves published posts) use the
  # static default card.
  defp put_og(conn, post) do
    image =
      if post.published_at,
        do: url(~p"/og/posts/#{post.slug}"),
        else: url(~p"/og-default.png")

    conn
    |> assign(:og_type, "article")
    |> assign(:og_title, post.title)
    |> assign(:og_description, post.excerpt)
    |> assign(:og_url, url(~p"/posts/#{post.slug}"))
    |> assign(:og_image, image)
  end

  # A signed-in admin previews any post (drafts included); everyone else sees only
  # published posts, plus the single draft unlocked by a matching ?p token.
  defp fetch_post(%{user: %{}}, slug, _token), do: Blog.get_post_by_slug!(slug)

  defp fetch_post(_scope, slug, token) when is_binary(token) do
    case Blog.get_post_by_preview_token(slug, token) do
      %Post{} = post -> {:preview, post}
      nil -> Blog.get_published_post!(slug)
    end
  end

  defp fetch_post(_scope, slug, _token), do: Blog.get_published_post!(slug)
end
