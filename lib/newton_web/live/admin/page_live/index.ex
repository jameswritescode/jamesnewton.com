defmodule NewtonWeb.Admin.PageLive.Index do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :pages, Newton.Pages.list_pages())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:pages}>
      <Components.page_header title="Pages">
        <Components.button navigate={~p"/admin/pages/new"}>New page</Components.button>
      </Components.page_header>

      <Components.list id="pages" empty="No pages yet.">
        <Components.list_item
          :for={{id, page} <- @streams.pages}
          id={id}
          navigate={~p"/admin/pages/#{page.id}/edit"}
        >
          {page.title}
          <:inline>
            <span class="text-[0.78rem] text-(--admin-text-subtle)">/{page.slug}</span>
          </:inline>
          <:meta>
            <Layouts.status_badge status={if page.published, do: :published, else: :draft} />
          </:meta>
        </Components.list_item>
      </Components.list>
    </Layouts.admin>
    """
  end
end
