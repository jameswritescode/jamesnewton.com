defmodule NewtonWeb.Admin.PostLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :posts, Newton.Blog.list_posts())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Newton.Blog.get_post!(id)
    {:ok, _} = Newton.Blog.delete_post(post)
    {:noreply, stream_delete(socket, :posts, post)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Posts</h1>
        <.link
          navigate={~p"/admin/posts/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          New post
        </.link>
      </div>

      <div
        id="posts"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div id="posts-empty" class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block">
          No posts yet.
        </div>
        <div
          :for={{id, post} <- @streams.posts}
          id={id}
          class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <.link
            navigate={~p"/admin/posts/#{post.id}/edit"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline"
          >
            {post.title}
          </.link>
          <.status_badge status={Newton.Blog.publish_status(post.published_at)} />
          <span class="w-28 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(post.published_at)}
          </span>
          <button
            type="button"
            phx-click="delete"
            phx-value-id={post.id}
            data-confirm="Delete this post?"
            class="rounded-md px-2 py-1 text-[0.75rem] text-(--admin-text-subtle) hover:text-(--admin-accent)"
          >
            Delete
          </button>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-2 py-0.5 text-[0.7rem] font-medium",
      @status == :published && "bg-(--admin-accent-soft) text-(--admin-accent)",
      @status == :draft && "border border-(--admin-border-strong) text-(--admin-text-subtle)",
      @status == :scheduled && "bg-(--admin-accent-soft) text-(--admin-accent)"
    ]}>
      {@status}
    </span>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")
end
