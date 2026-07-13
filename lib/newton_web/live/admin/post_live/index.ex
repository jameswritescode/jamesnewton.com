defmodule NewtonWeb.Admin.PostLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
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
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <Components.page_header title="Posts">
        <Components.button navigate={~p"/admin/posts/new"}>New post</Components.button>
      </Components.page_header>

      <div class="mb-4 flex gap-1 text-[0.8rem]">
        <.filter_tab filter={@filter} value={:all} label="All" />
        <.filter_tab filter={@filter} value={:drafts} label="Drafts" />
        <.filter_tab filter={@filter} value={:published} label="Published" />
      </div>

      <Components.list id="posts" empty="No posts yet.">
        <Components.list_item
          :for={{id, post} <- @streams.posts}
          id={id}
          navigate={~p"/admin/posts/#{post.id}/edit"}
        >
          {post.title}
          <:meta>
            <Layouts.status_badge status={Newton.Blog.publish_status(post.published_at)} />
          </:meta>
          <:meta>
            <span class="hidden w-28 text-right text-[0.78rem] text-(--admin-text-subtle) sm:block">
              {format_date(post.published_at, on_nil: "—")}
            </span>
          </:meta>
        </Components.list_item>
      </Components.list>
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
end
