defmodule NewtonWeb.Admin.GalleryLive.Show do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias Newton.Gallery.Storage
  alias NewtonWeb.Admin.{Components, Layouts}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    group = Gallery.get_group!(id)

    {:ok,
     socket
     |> assign(:page_title, group.title)
     |> assign(:group, group)
     |> assign(:dimensions, %{})
     |> stream(:photos, group.photos, dom_id: &"photo-#{&1.id}")
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 20,
       max_file_size: 50_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:editing_photo, nil)
    |> assign(:photo_form, nil)
  end

  defp apply_action(socket, :photo, %{"photo_id" => photo_id}) do
    photo = Gallery.get_photo!(photo_id)

    socket
    |> assign(:editing_photo, photo)
    |> assign(:photo_form, to_form(Gallery.change_photo(photo), as: :photo))
  end

  @impl true
  def handle_event("set_dimensions", %{"name" => name, "width" => w, "height" => h}, socket) do
    {:noreply, update(socket, :dimensions, &Map.put(&1, name, {w, h}))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("save_upload", _params, socket) do
    group = socket.assigns.group
    dimensions = socket.assigns.dimensions
    base = Gallery.next_position(group)

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        {:ok, key} = Storage.store(path, entry.client_name)
        {w, h} = Map.get(dimensions, entry.client_name, {nil, nil})
        {:ok, {key, w, h}}
      end)

    photos =
      uploaded
      |> Enum.with_index(base)
      |> Enum.map(fn {{key, w, h}, position} ->
        {:ok, photo} =
          Gallery.add_photo(group, %{
            image_key: key,
            alt: "",
            position: position,
            width: w,
            height: h
          })

        photo
      end)

    {:noreply, stream(socket, :photos, photos, at: -1)}
  end

  def handle_event("validate_photo", %{"photo" => params}, socket) do
    form =
      socket.assigns.editing_photo
      |> Gallery.change_photo(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :photo)

    {:noreply, assign(socket, :photo_form, form)}
  end

  def handle_event("save_photo", %{"photo" => params}, socket) do
    {:ok, photo} = Gallery.update_photo(socket.assigns.editing_photo, params)

    {:noreply,
     socket
     |> stream_insert(:photos, photo)
     |> push_patch(to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end

  def handle_event("close_photo", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end

  def handle_event("delete_photo", _params, socket) do
    photo = socket.assigns.editing_photo
    {:ok, _} = Gallery.delete_photo(photo)

    {:noreply,
     socket
     |> stream_delete(:photos, photo)
     |> push_patch(to: ~p"/admin/photos/#{socket.assigns.group.id}")}
  end

  def handle_event("reorder", %{"ids" => ids}, socket) do
    ordered_ids = Enum.map(ids, &String.to_integer/1)
    :ok = Gallery.reorder_photos(socket.assigns.group, ordered_ids)
    {:noreply, socket}
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

      <form
        id="upload-form"
        phx-submit="save_upload"
        phx-change="validate"
        phx-hook="ImageDimensions"
        class="mb-5"
      >
        <label
          class="flex cursor-pointer flex-col items-center justify-center rounded-xl border border-dashed border-(--admin-border) bg-(--admin-surface) px-6 py-8 text-center text-[0.85rem] text-(--admin-text-subtle) hover:border-(--admin-border-strong)"
          phx-drop-target={@uploads.photos.ref}
        >
          <.icon name="hero-arrow-up-tray" class="mb-2 size-6 text-(--admin-text-muted)" />
          Drag images here, or click to choose
          <.live_file_input upload={@uploads.photos} class="sr-only" />
        </label>

        <div :for={entry <- @uploads.photos.entries} class="mt-3 flex items-center gap-3 text-[0.8rem]">
          <span class="flex-1 truncate text-(--admin-text)">{entry.client_name}</span>
          <div class="h-1.5 w-32 overflow-hidden rounded-full bg-(--admin-bg)">
            <div class="h-full bg-(--admin-accent)" style={"width: #{entry.progress}%"}></div>
          </div>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            aria-label="Cancel"
            class="text-(--admin-text-subtle) hover:text-(--admin-accent)"
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>

        <p :for={err <- upload_errors(@uploads.photos)} class="mt-1 text-[0.78rem] text-(--admin-accent)">
          {upload_error_to_string(err)}
        </p>

        <button
          :if={@uploads.photos.entries != []}
          type="submit"
          class="mt-3 rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover)"
        >
          Upload {length(@uploads.photos.entries)} photo{if length(@uploads.photos.entries) == 1, do: "", else: "s"}
        </button>
      </form>

      <div
        id="photos"
        phx-hook="SortableGrid"
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
          draggable="true"
          data-id={photo.id}
          class="group relative aspect-square cursor-grab overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-bg) active:cursor-grabbing"
        >
          <.link patch={~p"/admin/photos/#{@group.id}/photo/#{photo.id}"} class="block size-full">
            <img src={Gallery.image_url(photo.image_key)} alt={photo.alt} class="size-full object-cover" />
          </.link>
          <span
            :if={photo.alt == ""}
            data-role="needs-alt"
            class="pointer-events-none absolute left-1.5 top-1.5 rounded bg-(--admin-accent) px-1.5 py-0.5 text-[0.65rem] font-medium text-white"
          >
            needs alt
          </span>
        </div>
      </div>

      <Components.drawer :if={@editing_photo} id="photo-drawer" on_close="close_photo">
        <:title>Photo</:title>

        <img
          src={Gallery.image_url(@editing_photo.image_key)}
          alt={@editing_photo.alt}
          class="aspect-square w-full rounded-lg object-cover"
        />

        <.form
          for={@photo_form}
          id="photo-form"
          phx-change="validate_photo"
          phx-submit="save_photo"
          class="flex flex-col gap-3"
        >
          <Components.field field={@photo_form[:alt]} type="textarea" label="Alt text" rows="2" />

          <div class="mt-2 flex items-center gap-2">
            <button
              type="button"
              phx-click="delete_photo"
              data-confirm="Delete this photo?"
              class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
            >
              Delete
            </button>
            <div class="flex-1"></div>
            <button
              type="submit"
              class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
            >
              Save
            </button>
          </div>
        </.form>
      </Components.drawer>
    </Layouts.admin>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 50MB)."
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 20)."
  defp upload_error_to_string(:not_accepted), do: "That file type isn't allowed."
  defp upload_error_to_string(_), do: "Upload error."
end
