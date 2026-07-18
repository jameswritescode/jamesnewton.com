defmodule NewtonWeb.Admin.DashboardLive do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts
  alias Newton.Blog.ImageAudit

  @impl true
  def mount(_params, _session, socket) do
    user_tz = socket.assigns.current_scope.user.timezone
    today = Newton.Analytics.local_today(user_tz)

    {:ok,
     socket
     |> assign(:posts_total, Newton.Blog.count_posts())
     |> assign(:posts_drafts, Newton.Blog.count_drafts())
     |> assign(:reading_total, Newton.Reading.count_entries())
     |> assign(:reading_active, Newton.Reading.count_in_progress())
     |> assign(:galleries_total, Newton.Gallery.count_groups())
     |> assign(:photos_total, Newton.Gallery.count_photos())
     |> assign(:media_drift, media_drift())
     |> assign(:local_today, today)
     |> assign(:views_week, Newton.Analytics.total_since(Date.add(today, -6), user_tz))
     |> assign(:views_total, Newton.Analytics.total_all_time())
     |> assign(:top_posts, top_posts(today, user_tz))
     |> assign(:week_series, week_series(today, user_tz))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:dashboard}>
      <Components.page_header title="Dashboard" />

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        <.card id="card-posts" title="Posts" primary={@posts_total} path="/admin/posts">
          {@posts_drafts} draft{if @posts_drafts == 1, do: "", else: "s"}
        </.card>
        <.card id="card-reading" title="Reading" primary={@reading_total} path="/admin/reading">
          {@reading_active} in progress
        </.card>
        <.card id="card-photos" title="Photos" primary={@galleries_total} path="/admin/photos">
          {@photos_total} photo{if @photos_total == 1, do: "", else: "s"}
        </.card>
        <.card id="card-views" title="Views" primary={@views_week}>
          {@views_total} all-time
        </.card>
      </div>

      <div class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div
          :if={@top_posts != []}
          id="top-posts"
          class="rounded-xl border border-(--admin-border) bg-(--admin-surface) p-4"
        >
          <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
            Top posts — last 7 days
          </h2>
          <ol class="flex flex-col gap-3">
            <li :for={post <- @top_posts}>
              <div class="flex items-baseline justify-between gap-3">
                <.link
                  :if={post.exists?}
                  href={~p"/posts/#{post.slug}"}
                  class="truncate text-[0.85rem] text-(--admin-text) no-underline hover:text-(--admin-accent)"
                >
                  {post.title}
                </.link>
                <span :if={!post.exists?} class="truncate text-[0.85rem] text-(--admin-text)">
                  {post.title}
                </span>
                <span class="font-mono text-[0.8rem] tabular-nums text-(--admin-text-muted)">
                  {post.count}
                </span>
              </div>
              <div class="mt-1.5 h-1 overflow-hidden rounded-full bg-(--admin-accent-soft)">
                <div
                  class="h-full rounded-full bg-(--admin-accent) opacity-60"
                  style={"width: #{bar_pct(post.count, @top_posts)}%"}
                >
                </div>
              </div>
            </li>
          </ol>
        </div>

        <div
          id="views-week"
          class="rounded-xl border border-(--admin-border) bg-(--admin-surface) p-4"
        >
          <h2 class="mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)">
            This week
          </h2>
          <div class="flex gap-2">
            <div :for={day <- @week_series} class="flex flex-1 flex-col gap-1.5">
              <div class="flex h-24 items-end">
                <div
                  class={[
                    "w-full rounded-sm bg-(--admin-accent)",
                    cond do
                      day.date == @local_today -> nil
                      day.future? -> "opacity-10"
                      true -> "opacity-35"
                    end
                  ]}
                  style={"height: #{day_pct(day.count, @week_series)}%"}
                  title={"#{day.date}: #{day.count}"}
                >
                </div>
              </div>
              <div class="text-center text-[0.68rem] uppercase text-(--admin-text-subtle)">
                {Calendar.strftime(day.date, "%a") |> String.slice(0, 2)}
              </div>
            </div>
          </div>
          <div class="mt-3 border-t border-(--admin-border) pt-2.5 text-[0.8rem] text-(--admin-text-subtle)">
            {week_summary(@week_series)}
          </div>
        </div>
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
  attr :path, :string, default: nil
  slot :inner_block, required: true

  defp card(%{path: nil} = assigns) do
    ~H"""
    <div
      id={@id}
      class="block rounded-xl border border-(--admin-border) bg-(--admin-surface) p-5 shadow-sm"
    >
      <div class="text-[0.78rem] font-medium text-(--admin-text-muted)">{@title}</div>
      <div class="mt-0.5 text-3xl font-semibold tracking-tight tabular-nums text-(--admin-text)">
        {@primary}
      </div>
      <div class="mt-0.5 text-[0.8rem] text-(--admin-text-subtle)">{render_slot(@inner_block)}</div>
    </div>
    """
  end

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

  defp top_posts(today, tz) do
    titles = Map.new(Newton.Blog.list_published_posts(), &{&1.slug, &1.title})

    today
    |> Date.add(-6)
    |> Newton.Analytics.top_paths(20, tz)
    |> Enum.flat_map(fn %{path: path, count: count} ->
      case path do
        "/posts/" <> slug ->
          [
            %{
              slug: slug,
              count: count,
              title: Map.get(titles, slug, path),
              exists?: Map.has_key?(titles, slug)
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.take(5)
  end

  defp week_series(today, tz) do
    monday = Date.beginning_of_week(today)
    totals = Map.new(Newton.Analytics.daily_totals(monday, tz), &{&1.date, &1.count})

    for offset <- 0..6 do
      date = Date.add(monday, offset)
      %{date: date, count: Map.get(totals, date, 0), future?: Date.compare(date, today) == :gt}
    end
  end

  # Bars scale against the biggest value in their group; 4% keeps zero-count
  # days visible as a baseline tick.
  defp day_pct(count, series) do
    max = series |> Enum.map(& &1.count) |> Enum.max() |> max(1)
    max(count / max * 100, 4.0) |> Float.round(1)
  end

  defp bar_pct(count, posts) do
    max = posts |> Enum.map(& &1.count) |> Enum.max() |> max(1)
    Float.round(count / max * 100, 1)
  end

  defp week_summary(series) do
    elapsed = Enum.reject(series, & &1.future?)
    total = elapsed |> Enum.map(& &1.count) |> Enum.sum()

    if total == 0 do
      "No views yet this week"
    else
      busiest = Enum.max_by(elapsed, & &1.count)

      "Busiest #{Calendar.strftime(busiest.date, "%A")} · #{div(total, length(elapsed))}/day average"
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
