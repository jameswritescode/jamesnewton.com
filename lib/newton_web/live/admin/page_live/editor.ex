defmodule NewtonWeb.Admin.PageLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Pages
  alias Newton.Pages.Page
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.DraftEditor
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.InlineImageUpload
  alias NewtonWeb.Admin.Layouts
  alias NewtonWeb.PublicationNotifier

  # The `_unused_` markers ride along with the staged params because
  # FormHelpers.keep_persisted_identity/2 reads them to tell an untouched blank
  # from one the author cleared. `published` is never staged: it moves through
  # the drawer alone.
  @autosave_fields ~w(title slug meta_description body_markdown)
  @untitled_title "Untitled"
  @untitled_slug_prefix "untitled-page"

  defp draft do
    %DraftEditor.Config{
      record: :page,
      change: &Pages.change_page/2,
      create: &Pages.create_page/1,
      update: &Pages.update_page/2,
      attach_image: &Pages.attach_image/3,
      autosave_fields: @autosave_fields,
      derived_field: :meta_description,
      placeholder_title: @untitled_title,
      untitled_slug_prefix: @untitled_slug_prefix,
      next_untitled_slug: &Pages.next_untitled_slug/0,
      published?: & &1.published,
      editing_published?: & &1.page.published,
      notify: &PublicationNotifier.notify_page_change/2,
      edit_path: fn page -> ~p"/admin/pages/#{page.id}/edit" end,
      load_saved: &assign_page(&1, &2, "Edit page")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:drawer_open, false)
     |> DraftEditor.mount()
     |> InlineImageUpload.allow(progress: &handle_inline_upload/3)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"page" => params} = payload, socket) do
    {:noreply, DraftEditor.apply_validate(socket, draft(), params, payload["_target"])}
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

  def handle_event("toggle_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, !socket.assigns.drawer_open)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, false)}
  end

  def handle_event("publish", _params, socket) do
    {:noreply, publish(socket, socket.assigns.page)}
  end

  def handle_event("unpublish", _params, socket) do
    {:noreply, set_published(socket, socket.assigns.page, false)}
  end

  def handle_event("toggle_sitemap", _params, socket) do
    {:noreply, set_in_sitemap(socket, socket.assigns.page, not socket.assigns.page.in_sitemap)}
  end

  def handle_event("upload_rejected", %{"rejected" => rejected}, socket) when is_list(rejected) do
    summary = InlineImageUpload.rejected_summary(rejected)
    {:noreply, put_flash(socket, :error, "Not uploaded: #{summary}")}
  end

  def handle_event("recover", %{"page" => params}, socket) do
    if params["lock_version"] == to_string(socket.assigns.page.lock_version) do
      {:noreply,
       socket
       |> DraftEditor.apply_validate(draft(), params, nil)
       |> assign(:editor_key, DraftEditor.new_editor_key())}
    else
      {:noreply,
       put_flash(socket, :info, "Updated in another window — showing the latest version.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Pages.delete_page(socket.assigns.page)
    PublicationNotifier.notify_page_change(socket.assigns.page, nil)

    {:noreply,
     socket
     |> put_flash(:info, "Page deleted")
     |> push_navigate(to: ~p"/admin/pages")}
  end

  @impl true
  def handle_info(:autosave, socket), do: {:noreply, DraftEditor.autosave(socket, draft())}

  defp apply_action(socket, :new, _params), do: assign_page(socket, %Page{}, "New page")

  defp apply_action(socket, :edit, %{"id" => id}),
    do: assign_page(socket, Pages.get_page!(id), "Edit page")

  defp assign_page(socket, %Page{} = page, page_title),
    do: DraftEditor.assign_record(socket, draft(), page, page_title)

  # Publishing an unsaved page has to create the row first: the drawer acts on
  # the staged form params rather than waiting for a manual save.
  defp publish(socket, %Page{id: nil}) do
    staged = Map.take(socket.assigns.form.source.params || %{}, @autosave_fields)

    if DraftEditor.content?(staged) do
      create_published(socket, staged)
    else
      put_flash(socket, :error, "Add a title or body before publishing")
    end
  end

  defp publish(socket, %Page{} = page), do: set_published(socket, page, true)

  defp create_published(socket, staged) do
    case DraftEditor.create(socket, draft(), Map.put(staged, "published", true)) do
      {:ok, page} ->
        socket
        |> assign(:page, page)
        |> assign(:autosave_params, nil)
        |> assign(:save_state, :saved)
        |> DraftEditor.claim_record(page)
        |> put_flash(:info, "Page published")
        |> push_patch(to: ~p"/admin/pages/#{page.id}/edit")

      {:error, changeset} ->
        assign(socket, :form, FormHelpers.failed_create_form(changeset))
    end
  end

  defp set_published(socket, %Page{} = page, published) do
    case Pages.update_page(page, %{"published" => published}) do
      {:ok, updated} ->
        PublicationNotifier.notify_page_change(page, updated)

        socket
        |> assign(:page, updated)
        |> assign(:slug_locked, DraftEditor.loaded_slug_locked?(draft(), updated))
        |> put_flash(:info, if(published, do: "Page published", else: "Moved to draft"))

      {:error, :stale} ->
        DraftEditor.enter_conflict(socket)

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
  end

  defp set_in_sitemap(socket, %Page{} = page, in_sitemap) do
    case Pages.update_page(page, %{"in_sitemap" => in_sitemap}) do
      {:ok, updated} ->
        PublicationNotifier.notify_page_change(page, updated)
        assign(socket, :page, updated)

      {:error, :stale} ->
        DraftEditor.enter_conflict(socket)

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
  end

  defp save(socket, %Page{id: nil}, params) do
    if DraftEditor.content?(params) do
      create_saved(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Add a title or body before saving")}
    end
  end

  defp save(socket, %Page{} = page, params) do
    case Pages.update_page(page, params) do
      {:ok, updated} ->
        PublicationNotifier.notify_page_change(page, updated)
        {:noreply, saved(socket)}

      {:error, :stale} ->
        {:noreply, DraftEditor.enter_conflict(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp create_saved(socket, params) do
    case DraftEditor.create(socket, draft(), params) do
      {:ok, _page} ->
        {:noreply, saved(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, FormHelpers.failed_create_form(changeset))}
    end
  end

  defp saved(socket) do
    socket
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> put_flash(:info, "Saved.")
    |> push_navigate(to: ~p"/admin/pages")
  end

  defp handle_inline_upload(:inline_images, entry, socket),
    do: DraftEditor.upload_progress(entry, socket, draft())

  defp save_state_label(:unsaved), do: "Unsaved changes…"
  defp save_state_label(:error), do: "Couldn't save"
  defp save_state_label(:conflict), do: "Changed in another window"
  defp save_state_label(_), do: "Saved"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:pages}>
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

        <div class="mb-4 flex flex-wrap items-center gap-3">
          <.link
            navigate={~p"/admin/pages"}
            class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)"
          >
            ← Pages
          </.link>
          <div class="flex-1"></div>
          <span :if={@save_state != :saved} class="text-[0.78rem] text-(--admin-text-subtle)">
            {save_state_label(@save_state)}
          </span>
          <Layouts.status_badge status={if @page.published, do: :published, else: :draft} />
          <Components.button variant="secondary" phx-click="toggle_drawer">
            Settings
          </Components.button>
          <Components.button type="submit">Save</Components.button>
        </div>

        <.input
          field={@form[:title]}
          type="text"
          placeholder="Title"
          phx-blur="autosave_now"
          class="mb-2 w-full border-none bg-transparent text-2xl font-semibold text-(--admin-text) focus:outline-none"
        />

        <.input
          field={@form[:slug]}
          type="text"
          placeholder="slug"
          phx-blur="autosave_now"
          class="mb-4 w-full border-none bg-transparent font-mono text-[0.8rem] text-(--admin-text-subtle) focus:outline-none"
        />

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

        <Components.markdown_editor
          key={@editor_key}
          field={@form[:body_markdown]}
          upload={@uploads.inline_images}
        />

        <label
          for={@form[:meta_description].id}
          class="mt-8 mb-3 flex items-baseline gap-2 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)"
        >
          Meta description
          <span class="normal-case tracking-normal text-(--admin-text-muted)">
            auto-derived from the body until you edit it
          </span>
        </label>
        <.input
          field={@form[:meta_description]}
          type="textarea"
          rows="2"
          class="w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-3 text-[0.85rem] text-(--admin-text) focus:outline-none"
        />
      </.form>

      <Components.drawer :if={@drawer_open} id="publish-drawer" on_close="close_drawer">
        <:title>Publish</:title>

        <div class="text-[0.78rem] text-(--admin-text-muted)">
          Status:
          <span class="font-medium text-(--admin-text)">
            {if @page.published, do: "published", else: "draft"}
          </span>
        </div>

        <div :if={@page.id} class="flex flex-col gap-1.5">
          <button
            id="sitemap-toggle"
            type="button"
            role="switch"
            aria-checked={to_string(@page.in_sitemap)}
            phx-click="toggle_sitemap"
            class="group flex w-full cursor-pointer items-center justify-between gap-3 text-left text-[0.8rem] text-(--admin-text)"
          >
            Include in sitemap
            <span class={[
              "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border transition-colors duration-150",
              if(@page.in_sitemap,
                do: "border-(--admin-accent) bg-(--admin-accent)",
                else:
                  "border-(--admin-border) bg-(--admin-surface) group-hover:border-(--admin-text-subtle)"
              )
            ]}>
              <span class={[
                "inline-block size-3.5 rounded-full shadow-sm transition-transform duration-150",
                if(@page.in_sitemap,
                  do: "translate-x-[1.1rem] bg-white",
                  else: "translate-x-0.5 bg-(--admin-text-subtle)"
                )
              ]}>
              </span>
            </span>
          </button>
          <p :if={not @page.published} class="text-[0.75rem] text-(--admin-text-subtle)">
            Only applies once the page is published.
          </p>
        </div>

        <div :if={@page.id} class="text-[0.78rem] text-(--admin-text-subtle)">
          <.link
            href={~p"/#{@page.slug}"}
            target="_blank"
            class="text-(--admin-accent) no-underline hover:underline"
          >
            View on site ↗
          </.link>
        </div>

        <Components.drawer_footer
          deletable?={@page.id != nil}
          delete_event="delete"
          delete_confirm="Delete this page permanently?"
        >
          <Components.button :if={not @page.published} phx-click="publish">
            Publish
          </Components.button>
          <Components.button :if={@page.published} variant="secondary" phx-click="unpublish">
            Move to draft
          </Components.button>
        </Components.drawer_footer>
      </Components.drawer>
    </Layouts.admin>
    """
  end
end
