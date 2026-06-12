defmodule NewtonWeb.Admin.GalleryLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Photos")
     |> stream(:galleries, Gallery.list_groups())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:photos}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Photos</h1>
        <.link
          patch={~p"/admin/photos/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add gallery
        </.link>
      </div>

      <div
        id="galleries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="galleries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No galleries yet.
        </div>
        <div
          :for={{id, group} <- @streams.galleries}
          id={id}
          class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <div class="size-10 shrink-0 overflow-hidden rounded-md bg-(--admin-bg)">
            <img
              :if={cover = List.first(group.photos)}
              src={Gallery.image_url(cover.image_key)}
              alt=""
              class="size-full object-cover"
            />
          </div>
          <.link
            navigate={~p"/admin/photos/#{group.id}"}
            class="flex-1 text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
          >
            {group.title}
          </.link>
          <span class="text-[0.78rem] text-(--admin-text-subtle)">
            {length(group.photos)} photo{if length(group.photos) == 1, do: "", else: "s"}
          </span>
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(group.taken_on)}
          </span>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
