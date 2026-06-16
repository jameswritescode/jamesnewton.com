defmodule NewtonWeb.Admin.PostLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    Newton.Blog.discard_empty_untitled_drafts()
    {:ok, stream(socket, :posts, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = parse_filter(params["filter"])

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:posts, Newton.Blog.list_posts(filter), reset: true)}
  end

  defp parse_filter("drafts"), do: :drafts
  defp parse_filter("published"), do: :published
  defp parse_filter(_), do: :all

  @impl true
  def handle_event("new_post", _params, socket) do
    {:ok, post} = Newton.Blog.create_draft()
    {:noreply, push_navigate(socket, to: ~p"/admin/posts/#{post.id}/edit")}
  end

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
        <button
          type="button"
          phx-click="new_post"
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover)"
        >
          New post
        </button>
      </div>

      <div class="mb-4 flex gap-1 text-[0.8rem]">
        <.filter_tab filter={@filter} value={:all} label="All" />
        <.filter_tab filter={@filter} value={:drafts} label="Drafts" />
        <.filter_tab filter={@filter} value={:published} label="Published" />
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
          class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <.link
            navigate={~p"/admin/posts/#{post.id}/edit"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
          >
            {post.title}
          </.link>
          <Layouts.status_badge status={Newton.Blog.publish_status(post.published_at)} />
          <span class="w-28 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(post.published_at)}
          </span>
          <button
            type="button"
            phx-click="delete"
            phx-value-id={post.id}
            data-confirm="Delete this post?"
            class="relative z-10 rounded-md px-2 py-1 text-[0.75rem] text-(--admin-text-subtle) hover:text-(--admin-accent)"
          >
            Delete
          </button>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :filter, :atom, required: true
  attr :value, :atom, required: true
  attr :label, :string, required: true

  defp filter_tab(assigns) do
    ~H"""
    <.link
      patch={~p"/admin/posts?filter=#{@value}"}
      class={[
        "rounded-md px-3 py-1 no-underline",
        @filter == @value && "bg-(--admin-accent-soft) font-medium text-(--admin-accent)",
        @filter != @value && "text-(--admin-text-muted) hover:bg-(--admin-accent-soft)"
      ]}
    >
      {@label}
    </.link>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")
end
