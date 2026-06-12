defmodule NewtonWeb.Admin.ReadingLive.Index do
  use NewtonWeb, :live_view

  alias Newton.Reading
  alias Newton.Reading.Entry
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.Layouts

  @status_options [
    {"Reading", :reading},
    {"Read", :read},
    {"Listening", :listening},
    {"Listened", :listened}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:status_options, @status_options)
     |> assign(:status_counts, Reading.status_counts())
     |> stream(:entries, Reading.list_entries())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Reading")
    |> assign(:drawer_open, false)
    |> assign(:entry, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    entry = %Entry{status: :reading}

    socket
    |> assign(:page_title, "New entry")
    |> assign(:drawer_open, true)
    |> assign(:entry, entry)
    |> assign(:form, to_form(Reading.change_entry(entry)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    entry = Reading.get_entry!(id)

    socket
    |> assign(:page_title, "Edit entry")
    |> assign(:drawer_open, true)
    |> assign(:entry, entry)
    |> assign(:form, to_form(Reading.change_entry(entry)))
  end

  @impl true
  def handle_event("validate", %{"entry" => params}, socket) do
    form =
      socket.assigns.entry
      |> Reading.change_entry(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"entry" => params}, socket) do
    save(socket, socket.assigns.entry, params)
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/reading")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = Reading.get_entry!(id)
    {:ok, _} = Reading.delete_entry(entry)

    {:noreply,
     socket
     |> put_flash(:info, "Entry deleted")
     |> refresh_entries()
     |> push_patch(to: ~p"/admin/reading")}
  end

  defp save(socket, %Entry{id: nil}, params) do
    case Reading.create_entry(params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry added")
         |> refresh_entries()
         |> push_patch(to: ~p"/admin/reading")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %Entry{} = entry, params) do
    case Reading.update_entry(entry, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry saved")
         |> refresh_entries()
         |> push_patch(to: ~p"/admin/reading")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp refresh_entries(socket) do
    socket
    |> stream(:entries, Reading.list_entries(), reset: true)
    |> assign(:status_counts, Reading.status_counts())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:reading}>
      <div class="mb-6 flex items-center justify-between">
        <h1 class="text-[1.35rem] font-semibold tracking-tight">Reading</h1>
        <.link
          patch={~p"/admin/reading/new"}
          class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white no-underline hover:bg-(--admin-accent-hover)"
        >
          Add entry
        </.link>
      </div>

      <.reading_summary counts={@status_counts} />

      <div
        id="entries"
        phx-update="stream"
        class="overflow-hidden rounded-xl border border-(--admin-border)"
      >
        <div
          id="entries-empty"
          class="hidden p-5 text-[0.85rem] text-(--admin-text-subtle) only:block"
        >
          No reading entries yet.
        </div>
        <div
          :for={{id, entry} <- @streams.entries}
          id={id}
          class="relative flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0 hover:bg-(--admin-accent-soft)"
        >
          <div class="flex min-w-0 flex-1 items-baseline gap-2">
            <.link
              patch={~p"/admin/reading/#{entry.id}/edit"}
              class="text-[0.9rem] font-medium text-(--admin-text) no-underline after:absolute after:inset-0"
            >
              {entry.title}
            </.link>
            <span class="truncate text-[0.8rem] text-(--admin-text-subtle)">{entry.author}</span>
          </div>
          <Layouts.reading_badge status={entry.status} />
          <span class="w-24 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(entry.finished_at)}
          </span>
        </div>
      </div>

      <.reading_drawer
        :if={@drawer_open}
        form={@form}
        entry={@entry}
        status_options={@status_options}
      />
    </Layouts.admin>
    """
  end

  attr :counts, :map, required: true

  defp reading_summary(assigns) do
    ~H"""
    <div
      id="reading-summary"
      class="mb-6 rounded-xl border border-(--admin-border) bg-(--admin-surface) p-4"
    >
      <.reading_bar
        label="Books"
        finished={@counts.read}
        in_progress={@counts.reading}
        finished_label="read"
        in_progress_label="reading"
      />
      <.reading_bar
        label="Audio"
        finished={@counts.listened}
        in_progress={@counts.listening}
        finished_label="listened"
        in_progress_label="listening"
      />
      <div class="mt-3 flex items-center gap-4 text-[0.72rem] text-(--admin-text-subtle)">
        <span class="flex items-center gap-1.5">
          <span class="size-2.5 rounded-sm bg-(--admin-accent)"></span> finished
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2.5 rounded-sm bg-(--admin-accent-soft)"></span> in progress
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :finished, :integer, required: true
  attr :in_progress, :integer, required: true
  attr :finished_label, :string, required: true
  attr :in_progress_label, :string, required: true

  defp reading_bar(assigns) do
    assigns = assign(assigns, :total, assigns.finished + assigns.in_progress)

    ~H"""
    <div class="mb-3 last:mb-0">
      <div class="mb-1 flex items-center justify-between text-[0.78rem]">
        <span class="font-medium text-(--admin-text)">{@label}</span>
        <span class="text-(--admin-text-subtle)">
          {@finished} {@finished_label} · {@in_progress} {@in_progress_label}
        </span>
      </div>
      <div class="flex h-2.5 overflow-hidden rounded-full bg-(--admin-bg)">
        <div
          :if={@total > 0}
          class="bg-(--admin-accent)"
          style={"width: #{percent(@finished, @total)}%"}
        >
        </div>
        <div
          :if={@total > 0}
          class="bg-(--admin-accent-soft)"
          style={"width: #{percent(@in_progress, @total)}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp percent(part, total), do: round(part / total * 100)

  attr :form, :map, required: true
  attr :entry, :map, required: true
  attr :status_options, :list, required: true

  defp reading_drawer(assigns) do
    ~H"""
    <Components.drawer id="reading-drawer" on_close="close_drawer">
      <:title>{if @entry.id, do: "Edit entry", else: "New entry"}</:title>

      <.form
        for={@form}
        id="reading-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-3"
      >
        <Components.field field={@form[:title]} label="Title" />
        <Components.field field={@form[:author]} label="Author" />
        <Components.field field={@form[:link]} label="Link" />
        <Components.field
          field={@form[:status]}
          type="select"
          label="Status"
          options={@status_options}
        />
        <Components.field field={@form[:finished_at]} type="date" label="Finished on" />
        <Components.field field={@form[:note]} type="textarea" label="Note" rows="3" />

        <div class="mt-2 flex items-center gap-2">
          <button
            :if={@entry.id}
            type="button"
            phx-click="delete"
            phx-value-id={@entry.id}
            data-confirm="Delete this entry?"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
          >
            Delete
          </button>
          <div class="flex-1"></div>
          <.link
            patch={~p"/admin/reading"}
            class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
          >
            Cancel
          </.link>
          <button
            type="submit"
            class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Save
          </button>
        </div>
      </.form>
    </Components.drawer>
    """
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")
end
