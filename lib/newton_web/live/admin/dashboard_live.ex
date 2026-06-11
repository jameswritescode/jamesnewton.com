defmodule NewtonWeb.Admin.DashboardLive do
  use NewtonWeb, :live_view

  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts_total, Newton.Blog.count_posts())
     |> assign(:posts_drafts, Newton.Blog.count_drafts())
     |> assign(:reading_total, Newton.Reading.count_entries())
     |> assign(:reading_active, Newton.Reading.count_in_progress())
     |> assign(:galleries_total, Newton.Gallery.count_groups())
     |> assign(:photos_total, Newton.Gallery.count_photos())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:dashboard}>
      <h1 class="admin-page-title">Dashboard</h1>

      <div class="admin-cards">
        <.card
          id="card-posts"
          title="Posts"
          primary={@posts_total}
          action="New post"
          path="/admin/posts"
        >
          {@posts_drafts} draft{if @posts_drafts == 1, do: "", else: "s"}
        </.card>
        <.card
          id="card-reading"
          title="Reading"
          primary={@reading_total}
          action="Add entry"
          path="/admin/reading"
        >
          {@reading_active} in progress
        </.card>
        <.card
          id="card-photos"
          title="Photos"
          primary={@galleries_total}
          action="New gallery"
          path="/admin/photos"
        >
          {@photos_total} photo{if @photos_total == 1, do: "", else: "s"}
        </.card>
      </div>
    </Layouts.admin>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :primary, :integer, required: true
  attr :action, :string, required: true
  attr :path, :string, required: true
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <section id={@id} class="admin-card">
      <div class="admin-card-label">{@title}</div>
      <div class="admin-card-value">{@primary}</div>
      <div class="admin-card-meta">{render_slot(@inner_block)}</div>
      <.link navigate={@path} class="admin-card-action">
        {@action} <span aria-hidden="true">→</span>
      </.link>
    </section>
    """
  end
end
