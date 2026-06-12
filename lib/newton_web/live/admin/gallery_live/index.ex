defmodule NewtonWeb.Admin.GalleryLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Gallery
  alias Newton.Gallery.PhotoGroup
  alias NewtonWeb.Admin.{FormHelpers, Layouts}
  alias NewtonWeb.Admin.GalleryLive.Components, as: GalleryComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :galleries, Gallery.list_groups())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Photos")
    |> assign(:drawer_open, false)
    |> assign(:group, nil)
    |> assign(:form, nil)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
  end

  defp apply_action(socket, :new, _params) do
    group = %PhotoGroup{}

    socket
    |> assign(:page_title, "New gallery")
    |> assign(:drawer_open, true)
    |> assign(:group, group)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
    |> assign(:form, to_form(Gallery.change_group(group), as: :group))
  end

  @impl true
  def handle_event("validate_settings", %{"group" => params}, socket) do
    slug_locked = socket.assigns.slug_locked or params["slug"] != socket.assigns.slug_auto

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        Newton.Slug.slugify(params["title"] || "")
      end)

    form =
      socket.assigns.group
      |> Gallery.change_group(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :group)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_locked, slug_locked)
     |> assign(:slug_auto, slug_auto)}
  end

  def handle_event("save_settings", %{"group" => params}, socket) do
    case Gallery.create_group(fill_blank_slug(params)) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gallery created")
         |> stream(:galleries, Gallery.list_groups(), reset: true)
         |> push_patch(to: ~p"/admin/photos")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :group))}
    end
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/photos")}
  end

  defp fill_blank_slug(%{"slug" => slug} = params) when slug not in [nil, ""], do: params

  defp fill_blank_slug(params) do
    Map.put(params, "slug", Newton.Slug.slugify(params["title"] || ""))
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

      <GalleryComponents.settings_drawer
        :if={@drawer_open}
        form={@form}
        editing?={false}
        cancel_path={~p"/admin/photos"}
      />
    </Layouts.admin>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
