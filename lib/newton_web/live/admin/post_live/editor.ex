defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias Newton.SocialCard
  alias Newton.Storage
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.DraftEditor
  alias NewtonWeb.Admin.InlineImageUpload
  alias NewtonWeb.Admin.Layouts
  alias NewtonWeb.PublicationNotifier

  # Autosave writes whatever it buffered without the publish-state scrubbing the
  # explicit "save" handler does, so only content fields are buffered. The
  # `_unused_` markers ride along because FormHelpers.keep_persisted_identity/2
  # reads them to tell an untouched blank from one the author cleared.
  # `published_at` is set from socket assigns, never from the client.
  @autosave_fields ~w(title slug excerpt body_markdown)
  @untitled_title "Untitled post"
  @untitled_slug_prefix "untitled-post"

  defp draft do
    %DraftEditor.Config{
      record: :post,
      change: &Blog.change_post/2,
      create: &Blog.create_post/1,
      update: &Blog.update_post/2,
      attach_image: &Blog.attach_image/3,
      autosave_fields: @autosave_fields,
      derived_field: :excerpt,
      placeholder_title: @untitled_title,
      untitled_slug_prefix: @untitled_slug_prefix,
      next_untitled_slug: &Blog.next_untitled_slug/0,
      published?: &(not is_nil(&1.published_at)),
      editing_published?: &(not is_nil(&1.published_at)),
      notify: &PublicationNotifier.notify_change/2,
      edit_path: fn post -> ~p"/admin/posts/#{post.id}/edit" end,
      load_saved: &assign_post(&1, &2, "Edit post")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:card_preview, nil)
     |> DraftEditor.mount()
     |> InlineImageUpload.allow(progress: &handle_inline_upload/3)}
  end

  defp handle_inline_upload(:inline_images, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_inline_upload(:inline_images, entry, socket) do
    {:noreply, socket} = DraftEditor.upload_progress(entry, socket, draft())

    {:noreply, assign(socket, :images, post_images(socket.assigns.post))}
  end

  defp post_images(%Post{id: nil}), do: []
  defp post_images(%Post{} = post), do: Blog.list_images(post)

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params), do: assign_post(socket, %Post{}, "New post")

  defp apply_action(socket, :edit, %{"id" => id}),
    do: assign_post(socket, Blog.get_post!(id), "Edit post")

  defp assign_post(socket, %Post{} = post, page_title) do
    socket
    |> DraftEditor.assign_record(draft(), post, page_title)
    |> assign(:images, post_images(post))
    |> assign(:published_at, post.published_at)
  end

  @impl true
  def handle_event("validate", %{"post" => params} = payload, socket) do
    {:noreply, DraftEditor.apply_validate(socket, draft(), params, payload["_target"])}
  end

  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "published_at", socket.assigns.published_at)
    save(socket, socket.assigns.post, params)
  end

  def handle_event("autosave_now", params, socket) do
    {:noreply, DraftEditor.autosave_now(socket, params)}
  end

  def handle_event("toggle_drawer", _params, socket) do
    socket = DraftEditor.toggle_drawer(socket)
    {:noreply, if(socket.assigns.drawer_open, do: put_card_preview(socket), else: socket)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, DraftEditor.close_drawer(socket)}
  end

  def handle_event("enable_preview", _params, socket) do
    {:ok, post} = Blog.enable_preview(socket.assigns.post)
    {:noreply, assign(socket, :post, post)}
  end

  def handle_event("disable_preview", _params, socket) do
    {:ok, post} = Blog.disable_preview(socket.assigns.post)
    {:noreply, assign(socket, :post, post)}
  end

  def handle_event("publish_now", _params, socket) do
    {:noreply, publish_now(socket, socket.assigns.post)}
  end

  def handle_event("unpublish", _params, socket) do
    {:noreply, set_published(socket, nil)}
  end

  def handle_event("set_publish_date", %{"date" => date}, socket) do
    case Date.from_iso8601(date) do
      {:ok, date} -> {:noreply, set_published(socket, DateTime.new!(date, ~T[12:00:00]))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    post = socket.assigns.post

    socket.assigns.images
    |> Enum.find(&(to_string(&1.id) == id))
    |> case do
      nil -> :ok
      image -> Blog.delete_image(image)
    end

    {:noreply, assign(socket, :images, post_images(post))}
  end

  def handle_event("upload_rejected", %{"rejected" => rejected}, socket) when is_list(rejected) do
    {:noreply, DraftEditor.upload_rejected(socket, rejected)}
  end

  def handle_event("conflict_load_latest", _params, socket) do
    case Blog.get_post(socket.assigns.post.id) do
      nil ->
        {:noreply, deleted_elsewhere(socket)}

      post ->
        {:noreply,
         socket
         |> assign_post(post, "Edit post")
         |> assign(:editor_key, DraftEditor.new_editor_key())}
    end
  end

  def handle_event("conflict_keep_mine", _params, socket) do
    case Blog.get_post(socket.assigns.post.id) do
      nil ->
        {:noreply, deleted_elsewhere(socket)}

      fresh ->
        params = socket.assigns.autosave_params || %{}

        case Blog.update_post(fresh, DraftEditor.never_blank_identity(params, fresh)) do
          {:ok, updated} ->
            PublicationNotifier.notify_change(fresh, updated)

            socket =
              socket
              |> assign(:post, updated)
              |> assign(:published_at, updated.published_at)
              |> assign(:form, to_form(Blog.change_post(updated)))
              |> assign(:save_state, :saved)
              |> assign(:autosave_params, nil)

            socket =
              if Map.has_key?(params, "body_markdown") do
                socket
              else
                assign(socket, :editor_key, DraftEditor.new_editor_key())
              end

            {:noreply, socket}

          {:error, :stale} ->
            {:noreply, DraftEditor.enter_conflict(socket)}

          {:error, _} ->
            {:noreply, assign(socket, :save_state, :error)}
        end
    end
  end

  def handle_event("recover", %{"post" => params}, socket) do
    {:noreply, DraftEditor.recover(socket, draft(), params)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)
    PublicationNotifier.notify_change(socket.assigns.post, nil)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> push_navigate(to: ~p"/admin/posts")}
  end

  defp deleted_elsewhere(socket) do
    socket
    |> put_flash(:error, "This post was deleted in another window.")
    |> push_navigate(to: ~p"/admin/posts")
  end

  @impl true
  def handle_info(:autosave, socket), do: {:noreply, DraftEditor.autosave(socket, draft())}

  attr :id, :string, required: true
  attr :event, :string, required: true
  slot :inner_block, required: true

  defp conflict_action(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click={@event}
      class="rounded-md border border-amber-600/40 px-3 py-1 text-[0.75rem] font-medium text-amber-800 transition-colors hover:border-amber-600/60 hover:bg-amber-500/15 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-600 admin-dark:border-amber-400/40 admin-dark:text-amber-200 admin-dark:hover:border-amber-400/60 admin-dark:hover:bg-amber-400/15"
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # Render the social card from the current form state (works for drafts/unsaved
  # edits, unlike the published-only public endpoint) and stash it as a data URI.
  defp put_card_preview(socket) do
    changeset = socket.assigns.form.source
    title = Ecto.Changeset.get_field(changeset, :title)

    attrs = %{
      title: if(title in [nil, ""], do: @untitled_title, else: title),
      published_on: socket.assigns.published_at && DateTime.to_date(socket.assigns.published_at),
      reading_time: socket.assigns.post.reading_time || 1
    }

    case SocialCard.post_card(attrs) do
      {:ok, png} -> assign(socket, :card_preview, "data:image/png;base64," <> Base.encode64(png))
      {:error, _reason} -> assign(socket, :card_preview, nil)
    end
  end

  defp save_state_label(:unsaved), do: "Unsaved changes…"
  defp save_state_label(:error), do: "Couldn't save"
  defp save_state_label(_), do: "Saved"

  # Drafts autosave: the Save button becomes the live indicator ("Saving…").
  defp saving?(published_at, save_state), do: is_nil(published_at) and save_state == :unsaved

  # Published posts show the text indicator (manual-save signal); drafts only show
  # it on error, since the button otherwise carries their state.
  defp show_save_text?(_published_at, :conflict), do: false

  defp show_save_text?(published_at, save_state) do
    (not is_nil(published_at) and save_state != :saved) or
      (is_nil(published_at) and save_state == :error)
  end

  defp publish_now(socket, %Post{id: nil}) do
    published_at = DateTime.truncate(DateTime.utc_now(), :second)

    DraftEditor.publish_new(socket, draft(), %{"published_at" => published_at}, fn socket, post ->
      socket
      |> assign(:post, post)
      |> assign(:published_at, post.published_at)
      |> assign(:slug_locked, DraftEditor.loaded_slug_locked?(draft(), post))
      |> assign(:autosave_params, nil)
      |> assign(:save_state, :saved)
      |> DraftEditor.claim_record(post)
      |> put_flash(:info, "Post published")
      |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")
    end)
  end

  defp publish_now(socket, %Post{}),
    do: set_published(socket, DateTime.truncate(DateTime.utc_now(), :second))

  # Publishing toggles publication state on the saved post; content edits in the
  # form are left untouched.
  defp set_published(socket, published_at) do
    before = socket.assigns.post

    case Blog.update_post(before, %{"published_at" => published_at}) do
      {:ok, post} ->
        PublicationNotifier.notify_change(before, post)

        socket
        |> assign(:post, post)
        |> assign(:published_at, post.published_at)
        |> put_flash(:info, if(post.published_at, do: "Post published", else: "Moved to draft"))

      {:error, :stale} ->
        socket
        |> update(:autosave_params, &Map.put(&1 || %{}, "published_at", published_at))
        |> DraftEditor.enter_conflict()

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
  end

  defp save(socket, %Post{id: nil}, params) do
    {:noreply,
     DraftEditor.save_new(socket, draft(), params, fn socket, post ->
       socket
       |> put_flash(:info, "Post saved")
       |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")
     end)}
  end

  defp save(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, updated} ->
        PublicationNotifier.notify_change(post, updated)

        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> assign(:post, updated)
         |> assign(:published_at, updated.published_at)
         |> assign(:form, to_form(Blog.change_post(updated)))
         |> assign(:save_state, :saved)
         |> assign(:autosave_params, nil)}

      {:error, :stale} ->
        {:noreply, socket |> assign(:autosave_params, params) |> DraftEditor.enter_conflict()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <.form
        for={@form}
        id="post-form"
        phx-submit="save"
        phx-change="validate"
        phx-auto-recover="recover"
      >
        <input type="hidden" name="post[lock_version]" value={@post.lock_version} />
        <div
          id="unsaved-guard"
          phx-hook="UnsavedGuard"
          data-unsaved={to_string(@save_state == :unsaved and not is_nil(@published_at))}
        >
        </div>
        <div class="mb-4 flex flex-wrap items-center gap-3">
          <.link
            navigate={~p"/admin/posts"}
            class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)"
          >
            ← Posts
          </.link>
          <div class="flex-1"></div>
          <span
            :if={show_save_text?(@published_at, @save_state)}
            class="text-[0.78rem] text-(--admin-text-subtle)"
          >
            {save_state_label(@save_state)}
          </span>
          <Layouts.status_badge status={Blog.publish_status(@published_at)} />
          <Components.button variant="secondary" phx-click="toggle_drawer">
            Settings
          </Components.button>
          <Components.button
            type="submit"
            disabled={saving?(@published_at, @save_state)}
            class="flex items-center gap-1.5 disabled:cursor-not-allowed disabled:opacity-70"
          >
            <span
              :if={saving?(@published_at, @save_state)}
              class="size-3 animate-spin rounded-full border-2 border-white/40 border-t-white"
            >
            </span>
            {if saving?(@published_at, @save_state), do: "Saving…", else: "Save"}
          </Components.button>
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
          id="conflict-banner"
          class="mb-3 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-amber-500/35 bg-amber-500/10 px-4 py-2.5 text-[0.8rem] text-amber-800 admin-dark:text-amber-200 motion-safe:animate-[admin-notice-in_160ms_ease-out]"
        >
          <.icon
            name="hero-exclamation-triangle-mini"
            class="size-4 shrink-0 text-amber-600 admin-dark:text-amber-300"
          />
          <span class="font-medium">This post was changed in another window</span>
          <div class="ml-auto flex items-center gap-2">
            <.conflict_action id="conflict-load-latest" event="conflict_load_latest">
              Load latest
            </.conflict_action>
            <.conflict_action id="conflict-keep-mine" event="conflict_keep_mine">
              Keep mine
            </.conflict_action>
          </div>
        </div>

        <Components.markdown_editor
          key={@editor_key}
          field={@form[:body_markdown]}
          upload={@uploads.inline_images}
        />

        <label
          for={@form[:excerpt].id}
          class="mt-8 mb-3 flex items-baseline gap-2 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)"
        >
          Excerpt
          <span class="normal-case tracking-normal text-(--admin-text-muted)">
            auto-derived from the body until you edit it
          </span>
        </label>
        <.input
          field={@form[:excerpt]}
          type="textarea"
          rows="2"
          class="w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-3 text-[0.85rem] text-(--admin-text) focus:outline-none"
        />
      </.form>

      <section :if={@images != []} id="post-images" class="mt-8">
        <Components.section_header title="Images" />
        <ul class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <li
            :for={image <- @images}
            id={"post-image-#{image.id}"}
            class="rounded-lg border border-(--admin-border) bg-(--admin-surface) p-2"
          >
            <img
              src={Storage.url(image.key)}
              alt=""
              class="h-24 w-full rounded object-cover"
            />
            <div class="mt-2 flex items-center justify-between gap-2 text-[0.72rem] text-(--admin-text-subtle)">
              <span class="truncate">{image.original_filename || image.key}</span>
              <%= if Blog.image_referenced?(@post, image) do %>
                <span class="shrink-0 text-(--admin-text-muted)">in use</span>
              <% else %>
                <span class="shrink-0 text-amber-400/80">not referenced</span>
                <button
                  type="button"
                  phx-click="delete_image"
                  phx-value-id={image.id}
                  data-confirm="Delete this image file? This cannot be undone."
                  class="shrink-0 text-red-400 hover:text-red-300"
                >
                  Delete
                </button>
              <% end %>
            </div>
          </li>
        </ul>
      </section>

      <Components.drawer :if={@drawer_open} id="publish-drawer" on_close="close_drawer">
        <:title>Publish</:title>

        <div class="text-[0.78rem] text-(--admin-text-muted)">
          Status:
          <span class="font-medium text-(--admin-text)">{Blog.publish_status(@published_at)}</span>
        </div>

        <form :if={@published_at} id="publish-date-form" phx-change="set_publish_date">
          <label class="block text-[0.78rem] text-(--admin-text-muted)">
            Publish date
            <input
              type="date"
              name="date"
              value={Date.to_iso8601(DateTime.to_date(@published_at))}
              class="mt-1 w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-2 py-1 text-[0.8rem] text-(--admin-text) focus:outline-none"
            />
          </label>
        </form>

        <div class="text-[0.78rem] text-(--admin-text-subtle)">
          Reading time · {@post.reading_time || "—"} min
          <.link
            :if={@post.id}
            href={~p"/posts/#{@post.slug}"}
            target="_blank"
            class="ml-2 text-(--admin-accent) no-underline hover:underline"
          >
            View on site ↗
          </.link>
        </div>

        <div :if={@card_preview} class="border-t border-(--admin-border) pt-3">
          <div class="mb-2 text-[0.78rem] font-medium text-(--admin-text)">Social card</div>
          <img
            id="og-card-preview"
            src={@card_preview}
            alt="Social card preview"
            class="w-full rounded-lg border border-(--admin-border)"
          />
        </div>

        <div :if={not Post.live?(@published_at)} class="border-t border-(--admin-border) pt-3">
          <div class="mb-1 text-[0.78rem] font-medium text-(--admin-text)">Preview link</div>
          <%= cond do %>
            <% is_nil(@post.id) -> %>
              <p class="text-[0.75rem] text-(--admin-text-subtle)">
                Save the draft to share a preview.
              </p>
            <% @post.preview_token -> %>
              <input
                id="preview-link-url"
                type="text"
                readonly
                value={url(~p"/posts/#{@post.slug}?#{[p: @post.preview_token]}")}
                class="w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-2 py-1 text-[0.75rem] text-(--admin-text-muted) focus:outline-none"
              />
              <div class="mt-2 flex gap-2">
                <Components.button
                  id="copy-preview-link"
                  phx-hook="CopyText"
                  data-clipboard-text={url(~p"/posts/#{@post.slug}?#{[p: @post.preview_token]}")}
                >
                  Copy
                </Components.button>
                <Components.button variant="secondary" phx-click="disable_preview">
                  Turn off preview link
                </Components.button>
              </div>
            <% true -> %>
              <Components.button variant="secondary" phx-click="enable_preview">
                Enable preview link
              </Components.button>
          <% end %>
        </div>

        <Components.drawer_footer
          deletable?={@post.id != nil}
          delete_event="delete"
          delete_confirm="Delete this post permanently?"
        >
          <Components.button
            :if={Blog.publish_status(@published_at) != :published}
            phx-click="publish_now"
          >
            Publish now
          </Components.button>
          <Components.button
            :if={Blog.publish_status(@published_at) != :draft}
            variant="secondary"
            phx-click="unpublish"
          >
            Move to draft
          </Components.button>
        </Components.drawer_footer>
      </Components.drawer>
    </Layouts.admin>
    """
  end
end
