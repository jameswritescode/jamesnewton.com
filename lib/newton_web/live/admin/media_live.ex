defmodule NewtonWeb.Admin.MediaLive do
  use NewtonWeb, :live_view

  import Ecto.Query

  alias Newton.Blog.ImageAudit
  alias Newton.Gallery
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_audit(socket)}
  end

  @impl true
  def handle_event("delete_stray", %{"key" => key}, socket) do
    ImageAudit.delete_stray(key)
    {:noreply, load_audit(socket)}
  end

  defp load_audit(socket) do
    audit = ImageAudit.run()
    slugs = audit.missing |> Enum.map(fn {slug, _key} -> slug end) |> Enum.uniq()

    post_ids =
      Map.new(
        Newton.Repo.all(
          from p in Newton.Blog.Post, where: p.slug in ^slugs, select: {p.slug, p.id}
        )
      )

    socket
    |> assign(:strays, Enum.map(audit.strays, &stray_entry/1))
    |> assign(:missing, audit.missing)
    |> assign(:post_ids, post_ids)
  end

  defp stray_entry(key) do
    root = Application.fetch_env!(:newton, :media_root)

    size =
      case File.stat(Path.join(root, key)) do
        {:ok, %{size: size}} -> size
        {:error, _} -> 0
      end

    %{key: key, dom_id: "media-stray-#{Path.rootname(key)}", size: size}
  end

  defp format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_000, do: "#{div(bytes, 1_000)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:media}>
      <Components.page_header title="Media" />

      <section id="media-strays" class="mb-8">
        <Components.section_header title="Orphaned files" />
        <p :if={@strays == []} class="text-[0.85rem] text-(--admin-text-muted)">
          No orphaned files.
        </p>
        <ul :if={@strays != []} class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <li
            :for={stray <- @strays}
            id={stray.dom_id}
            class="rounded-lg border border-(--admin-border) bg-(--admin-surface) p-2"
          >
            <img src={Gallery.image_url(stray.key)} alt="" class="h-24 w-full rounded object-cover" />
            <div class="mt-2 flex items-center justify-between gap-2 text-[0.72rem] text-(--admin-text-subtle)">
              <span class="truncate">{stray.key} · {format_bytes(stray.size)}</span>
              <button
                type="button"
                phx-click="delete_stray"
                phx-value-key={stray.key}
                data-confirm="Delete this file? Nothing references it, and this cannot be undone."
                class="shrink-0 text-red-400 hover:text-red-300"
              >
                Delete
              </button>
            </div>
          </li>
        </ul>
      </section>

      <section id="media-missing">
        <Components.section_header title="Missing files" />
        <p :if={@missing == []} class="text-[0.85rem] text-(--admin-text-muted)">
          No missing files.
        </p>
        <ul :if={@missing != []} class="flex flex-col gap-1.5">
          <li :for={{slug, key} <- @missing} class="text-[0.85rem] text-(--admin-text)">
            <span class="font-mono text-[0.78rem]">{key}</span>
            referenced by
            <.link
              :if={@post_ids[slug]}
              navigate={~p"/admin/posts/#{@post_ids[slug]}/edit"}
              class="text-(--admin-accent)"
            >
              {slug}
            </.link>
            <span :if={!@post_ids[slug]}>{slug}</span>
          </li>
        </ul>
      </section>
    </Layouts.admin>
    """
  end
end
