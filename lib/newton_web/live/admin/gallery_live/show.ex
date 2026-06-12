defmodule NewtonWeb.Admin.GalleryLive.Show do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    group = Gallery.get_group!(id)

    {:ok,
     socket
     |> assign(:page_title, group.title)
     |> assign(:group, group)
     |> stream(:photos, group.photos, dom_id: &"photo-#{&1.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:photos}>
      <div class="mb-4 flex items-center gap-3">
        <.link
          navigate={~p"/admin/photos"}
          class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)"
        >
          ← Photos
        </.link>
        <h1 class="text-[1.35rem] font-semibold tracking-tight">{@group.title}</h1>
        <div class="flex-1"></div>
        <.link
          patch={~p"/admin/photos/#{@group.id}/edit"}
          class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-text) no-underline hover:bg-(--admin-accent-soft)"
        >
          Settings
        </.link>
      </div>

      <div
        id="photos"
        phx-update="stream"
        class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4"
      >
        <div
          id="photos-empty"
          class="col-span-full hidden rounded-xl border border-dashed border-(--admin-border) p-8 text-center text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No photos yet — drag images here to start.
        </div>
        <div
          :for={{id, photo} <- @streams.photos}
          id={id}
          class="group relative aspect-square overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-bg)"
        >
          <img src={Gallery.image_url(photo.image_key)} alt={photo.alt} class="size-full object-cover" />
          <span
            :if={photo.alt == ""}
            data-role="needs-alt"
            class="absolute left-1.5 top-1.5 rounded bg-(--admin-accent) px-1.5 py-0.5 text-[0.65rem] font-medium text-white"
          >
            needs alt
          </span>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
