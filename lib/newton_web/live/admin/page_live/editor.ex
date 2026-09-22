defmodule NewtonWeb.Admin.PageLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Pages
  alias Newton.Pages.Page
  alias NewtonWeb.Admin.Autosave
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.InlineImageUpload
  alias NewtonWeb.Admin.Layouts

  @autosave_fields ~w(title slug meta_description body_markdown)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:save_state, :saved)
     |> assign(:autosave_params, nil)
     |> assign(:autosave_timer, nil)
     |> assign(:editor_key, new_editor_key())
     |> assign(:editor_page_id, :unset)
     |> allow_upload(:inline_images,
       accept: InlineImageUpload.accept(),
       max_entries: InlineImageUpload.max_entries(),
       max_file_size: InlineImageUpload.max_file_size(),
       auto_upload: true,
       progress: &handle_inline_upload/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"page" => params}, socket) do
    {:noreply, apply_validate(socket, params)}
  end

  def handle_event("save", %{"page" => params}, socket) do
    save(socket, socket.assigns.page, params)
  end

  def handle_event("autosave_now", _params, %{assigns: %{save_state: :conflict}} = socket) do
    {:noreply, socket}
  end

  def handle_event("autosave_now", params, socket) do
    socket =
      case params do
        %{"body_markdown" => body} ->
          update(socket, :autosave_params, &Map.put(&1 || %{}, "body_markdown", body))

        _ ->
          socket
      end

    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)
    send(self(), :autosave)
    {:noreply, assign(socket, :autosave_timer, nil)}
  end

  def handle_event("upload_rejected", %{"rejected" => rejected}, socket) when is_list(rejected) do
    summary = InlineImageUpload.rejected_summary(rejected)
    {:noreply, put_flash(socket, :error, "Not uploaded: #{summary}")}
  end

  def handle_event("recover", %{"page" => params}, socket) do
    if params["lock_version"] == to_string(socket.assigns.page.lock_version) do
      {:noreply, socket |> apply_validate(params) |> assign(:editor_key, new_editor_key())}
    else
      {:noreply,
       put_flash(socket, :info, "Updated in another window — showing the latest version.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Pages.delete_page(socket.assigns.page)

    {:noreply,
     socket
     |> put_flash(:info, "Page deleted")
     |> push_navigate(to: ~p"/admin/pages")}
  end

  @impl true
  def handle_info(:autosave, socket) do
    if not socket.assigns.page.published and socket.assigns.autosave_params do
      persist_autosave(socket, socket.assigns.page, socket.assigns.autosave_params)
    else
      {:noreply, socket}
    end
  end

  defp apply_action(socket, :new, _params), do: assign_page(socket, %Page{}, "New page")

  defp apply_action(socket, :edit, %{"id" => id}),
    do: assign_page(socket, Pages.get_page!(id), "Edit page")

  defp assign_page(socket, %Page{} = page, page_title) do
    socket
    |> sync_editor_key(page.id)
    |> assign(:page_title, page_title)
    |> assign(:page, page)
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Pages.change_page(page)))
  end

  # The body editor's DOM is phx-update="ignore", so patching to a DIFFERENT page
  # would leave the previous page's content in CodeMirror. Changing the key (and
  # with it every id in the region) forces morphdom to rebuild it; the key
  # survives the /new -> /:id/edit patch of one editing session because
  # ensure_page/persist_autosave pre-assign the new page id.
  defp sync_editor_key(socket, page_id) do
    case socket.assigns.editor_page_id do
      :unset ->
        assign(socket, :editor_page_id, page_id)

      ^page_id ->
        socket

      _changed ->
        socket |> assign(:editor_key, new_editor_key()) |> assign(:editor_page_id, page_id)
    end
  end

  defp new_editor_key, do: "ed#{System.unique_integer([:positive])}"

  defp apply_validate(socket, params) do
    form =
      socket.assigns.page
      |> Pages.change_page(params)
      |> Map.put(:action, :validate)
      |> to_form()

    socket
    |> assign(:form, form)
    |> track_save_state(params)
  end

  defp track_save_state(%{assigns: %{save_state: :conflict}} = socket, params) do
    assign(socket, :autosave_params, Autosave.content_params(params, @autosave_fields))
  end

  defp track_save_state(%{assigns: %{page: %Page{published: true}}} = socket, params) do
    dirty? = Autosave.dirty?(params, socket.assigns.page, @autosave_fields)
    assign(socket, :save_state, if(dirty?, do: :unsaved, else: :saved))
  end

  defp track_save_state(socket, params) do
    socket
    |> assign(:autosave_params, Autosave.content_params(params, @autosave_fields))
    |> assign(:save_state, :unsaved)
    |> assign(:autosave_timer, Autosave.schedule(socket.assigns.autosave_timer))
  end

  defp persist_autosave(socket, %Page{id: nil}, params) do
    if content?(params) do
      case Pages.create_page(backfill_new(params)) do
        {:ok, page} ->
          {:noreply,
           socket
           |> assign(:page, page)
           |> assign(:autosave_params, nil)
           |> assign(:autosave_timer, nil)
           |> assign(:save_state, :saved)
           |> assign(:editor_page_id, page.id)
           |> push_patch(to: ~p"/admin/pages/#{page.id}/edit")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, assign(socket, :save_state, :saved)}
    end
  end

  defp persist_autosave(socket, %Page{} = page, params) do
    case Pages.update_page(page, never_blank_identity(params, page)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:page, updated)
         |> assign(:autosave_params, nil)
         |> assign(:autosave_timer, nil)
         |> assign(:save_state, :saved)}

      {:error, :stale} ->
        {:noreply, enter_conflict(socket)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :save_state, :error)}
    end
  end

  defp save(socket, %Page{id: nil}, params) do
    case Pages.create_page(backfill_new(params)) do
      {:ok, _page} -> {:noreply, saved(socket)}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %Page{} = page, params) do
    case Pages.update_page(page, params) do
      {:ok, _updated} ->
        {:noreply, saved(socket)}

      {:error, :stale} ->
        {:noreply, enter_conflict(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp saved(socket) do
    socket
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/admin/pages")
  end

  defp enter_conflict(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:save_state, :conflict)
  end

  defp content?(params) do
    not blank?(params["title"]) or not blank?(params["body_markdown"])
  end

  defp backfill_new(params) do
    params
    |> keep_existing("title", "Untitled")
    |> keep_existing("slug", next_untitled_slug())
  end

  defp never_blank_identity(params, %Page{} = page) do
    params
    |> keep_existing("title", page.title)
    |> keep_existing("slug", page.slug)
  end

  defp keep_existing(params, key, existing) do
    if blank?(params[key]), do: Map.put(params, key, existing), else: params
  end

  defp next_untitled_slug, do: "untitled-page-#{System.unique_integer([:positive])}"

  defp handle_inline_upload(:inline_images, entry, socket) do
    InlineImageUpload.handle_progress(entry, socket, %{
      name: :inline_images,
      ensure: &ensure_page/1,
      attach: &attach_image/3
    })
  end

  # The first image dropped into an unsaved page needs a row to hang the ledger
  # entry on, so it creates the draft and moves to its edit URL.
  defp ensure_page(%{assigns: %{page: %Page{id: nil}}} = socket) do
    case Pages.create_page(%{"title" => "Untitled", "slug" => next_untitled_slug()}) do
      {:ok, page} ->
        socket =
          socket
          |> assign(:page, page)
          |> assign(:editor_page_id, page.id)
          |> push_patch(to: ~p"/admin/pages/#{page.id}/edit")

        {socket, page}

      {:error, _changeset} ->
        {socket, socket.assigns.page}
    end
  end

  defp ensure_page(socket), do: {socket, socket.assigns.page}

  defp attach_image(%Page{id: nil}, _key, _original_filename), do: :ok

  defp attach_image(%Page{} = page, key, original_filename) do
    Pages.attach_image(page, key, original_filename)
    :ok
  end

  defp save_state_label(:unsaved), do: "Unsaved changes…"
  defp save_state_label(:error), do: "Couldn't save"
  defp save_state_label(:conflict), do: "Changed in another window"
  defp save_state_label(_), do: "Saved"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:pages}>
      <Components.page_header title={@page_title}>
        <div class="flex items-center gap-3">
          <span
            :if={@save_state != :saved}
            class="text-[0.78rem] text-(--admin-text-subtle)"
          >
            {save_state_label(@save_state)}
          </span>
          <Layouts.status_badge status={if @page.published, do: :published, else: :draft} />
          <Components.button :if={@page.id} id="page-delete" variant="danger" phx-click="delete">
            Delete
          </Components.button>
          <Components.button type="submit" form="page-form">Save</Components.button>
        </div>
      </Components.page_header>

      <div
        :if={@save_state == :conflict}
        id="page-conflict-banner"
        class="mb-4 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-amber-500/35 bg-amber-500/10 px-4 py-2.5 text-[0.8rem] text-amber-800 admin-dark:text-amber-200"
      >
        <.icon
          name="hero-exclamation-triangle-mini"
          class="size-4 shrink-0 text-amber-600 admin-dark:text-amber-300"
        />
        <span class="font-medium">This page was changed in another window</span>
        <.link
          navigate={~p"/admin/pages/#{@page.id}/edit"}
          class="ml-auto font-medium text-amber-800 underline admin-dark:text-amber-200"
        >
          Load latest
        </.link>
      </div>

      <.form
        for={@form}
        id="page-form"
        phx-submit="save"
        phx-change="validate"
        phx-auto-recover="recover"
      >
        <input type="hidden" name="page[lock_version]" value={@page.lock_version} />
        <div
          id="unsaved-guard"
          phx-hook="UnsavedGuard"
          data-unsaved={to_string(@save_state == :unsaved and @page.published)}
        >
        </div>

        <div class="mb-4 grid gap-4 sm:grid-cols-2">
          <Components.field field={@form[:title]} label="Title" phx-blur="autosave_now" />
          <Components.field field={@form[:slug]} label="Slug" phx-blur="autosave_now" />
        </div>

        <div class="mb-4">
          <Components.field
            field={@form[:meta_description]}
            type="textarea"
            rows="2"
            label="Meta description"
          />
        </div>

        <Components.markdown_editor
          key={@editor_key}
          field={@form[:body_markdown]}
          upload={@uploads.inline_images}
        />

        <div class="mt-4">
          <.input
            field={@form[:published]}
            type="checkbox"
            label="Published"
            class="size-4 accent-(--admin-accent)"
          />
        </div>
      </.form>
    </Layouts.admin>
    """
  end
end
