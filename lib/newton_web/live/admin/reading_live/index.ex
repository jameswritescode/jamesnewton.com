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
     |> assign(:series_names, Reading.series_names())
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
    |> assign(:series_names, Reading.series_names())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:reading}>
      <Components.page_header title="Reading">
        <Components.button patch={~p"/admin/reading/new"}>Add entry</Components.button>
      </Components.page_header>

      <.reading_summary counts={@status_counts} />

      <Components.list id="entries" empty="No reading entries yet.">
        <Components.list_item
          :for={{id, entry} <- @streams.entries}
          id={id}
          patch={~p"/admin/reading/#{entry.id}/edit"}
        >
          {entry.title}
          <:inline>
            <span class="truncate text-[0.8rem] text-(--admin-text-subtle)">{entry.author}</span>
          </:inline>
          <:meta>
            <Layouts.reading_badge status={entry.status} />
          </:meta>
          <:meta>
            <span class="w-36 text-right text-[0.78rem] text-(--admin-text-subtle)">
              {format_date(entry.finished_at, on_nil: "—")}
            </span>
          </:meta>
        </Components.list_item>
      </Components.list>

      <.reading_drawer
        :if={@drawer_open}
        form={@form}
        entry={@entry}
        status_options={@status_options}
        series_names={@series_names}
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
  attr :series_names, :list, required: true

  defp reading_drawer(assigns) do
    ~H"""
    <Components.drawer id="reading-drawer" on_close="close_drawer">
      <:title>{if @entry.id, do: "Edit entry", else: "New entry"}</:title>

      <.form
        for={@form}
        id="reading-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-1 flex-col gap-3"
      >
        <Components.field field={@form[:title]} label="Title" />
        <Components.field field={@form[:author]} label="Author" />
        <Components.field field={@form[:series]} label="Series" list="series-names" />
        <datalist id="series-names">
          <option :for={name <- @series_names} value={name}></option>
        </datalist>
        <Components.field field={@form[:link]} label="Link" />
        <Components.field
          field={@form[:status]}
          type="select"
          label="Status"
          options={@status_options}
        />
        <Components.field field={@form[:finished_at]} type="date" label="Finished on" />
        <Components.field field={@form[:note]} type="textarea" label="Note" rows="3" />

        <Components.drawer_footer
          cancel_path={~p"/admin/reading"}
          deletable?={@entry.id != nil}
          delete_event="delete"
          delete_id={@entry.id}
          delete_confirm="Delete this entry?"
        >
          <Components.save_button />
        </Components.drawer_footer>
      </.form>
    </Components.drawer>
    """
  end
end
