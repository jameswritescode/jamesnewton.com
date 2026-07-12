defmodule NewtonWeb.Admin.DashboardLive do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts
  alias Newton.Blog.ImageAudit

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts_total, Newton.Blog.count_posts())
     |> assign(:posts_drafts, Newton.Blog.count_drafts())
     |> assign(:reading_total, Newton.Reading.count_entries())
     |> assign(:reading_active, Newton.Reading.count_in_progress())
     |> assign(:galleries_total, Newton.Gallery.count_groups())
     |> assign(:photos_total, Newton.Gallery.count_photos())
     |> assign(:media_drift, media_drift())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:dashboard}>
      <h1 class="mb-6 text-[1.35rem] font-semibold tracking-tight">Dashboard</h1>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
        <.card id="card-posts" title="Posts" primary={@posts_total} path="/admin/posts">
          {@posts_drafts} draft{if @posts_drafts == 1, do: "", else: "s"}
        </.card>
        <.card id="card-reading" title="Reading" primary={@reading_total} path="/admin/reading">
          {@reading_active} in progress
        </.card>
        <.card id="card-photos" title="Photos" primary={@galleries_total} path="/admin/photos">
          {@photos_total} photo{if @photos_total == 1, do: "", else: "s"}
        </.card>
      </div>

      <.link
        :if={@media_drift}
        id="media-drift"
        navigate={~p"/admin/media"}
        class="mt-4 block rounded-xl border border-amber-500/40 bg-(--admin-surface) p-4 text-[0.85rem] text-(--admin-text) no-underline hover:border-amber-500/70"
      >
        {drift_summary(@media_drift)} →
      </.link>
    </Layouts.admin>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :primary, :integer, required: true
  attr :path, :string, required: true
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="group block rounded-xl border border-(--admin-border) bg-(--admin-surface) p-5 shadow-sm no-underline transition-colors hover:border-(--admin-border-strong)"
    >
      <div class="flex items-center justify-between text-[0.78rem] font-medium text-(--admin-text-muted)">
        {@title}
        <span
          aria-hidden="true"
          class="text-(--admin-text-subtle) transition-transform group-hover:translate-x-0.5 group-hover:text-(--admin-accent)"
        >
          →
        </span>
      </div>
      <div class="mt-0.5 text-3xl font-semibold tracking-tight tabular-nums text-(--admin-text)">
        {@primary}
      </div>
      <div class="mt-0.5 text-[0.8rem] text-(--admin-text-subtle)">{render_slot(@inner_block)}</div>
    </.link>
    """
  end

  defp media_drift do
    case ImageAudit.run() do
      %{missing: [], strays: []} -> nil
      audit -> audit
    end
  end

  defp drift_summary(%{strays: strays, missing: missing}) do
    [
      count_phrase(length(strays), "orphaned file"),
      count_phrase(length(missing), "missing image")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp count_phrase(0, _noun), do: nil
  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(n, noun), do: "#{n} #{noun}s"
end
