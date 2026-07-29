defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  require Logger

  alias Newton.Blog
  alias Newton.Blog.Post
  alias Newton.Gallery
  alias Newton.Gallery.Storage
  alias Newton.SocialCard
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.Layouts
  alias NewtonWeb.PublicationNotifier

  @autosave_debounce_ms 1500

  @upload_accept ~w(.jpg .jpeg .png .webp .gif)
  @upload_max_entries 10
  @upload_max_file_size 50_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:drawer_open, false)
     |> assign(:card_preview, nil)
     |> assign(:save_state, :saved)
     |> assign(:autosave_params, nil)
     |> assign(:autosave_timer, nil)
     |> assign(:editor_key, new_editor_key())
     |> assign(:editor_post_id, :unset)
     |> allow_upload(:inline_images,
       accept: @upload_accept,
       max_entries: @upload_max_entries,
       max_file_size: @upload_max_file_size,
       auto_upload: true,
       progress: &handle_inline_upload/3
     )}
  end

  # Auto-upload progress callback: when an entry finishes, store it on the media
  # volume, record it on the post's image ledger, and push the URL back to the
  # editor hook to replace that upload's placeholder.
  defp handle_inline_upload(:inline_images, entry, socket) do
    if entry.done? do
      socket = ensure_post(socket)
      post = socket.assigns.post
      {token, filename} = split_upload_token(entry.client_name)

      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Storage.store(path, filename) do
            {:ok, key} ->
              attach_image(post, key, filename)
              {:ok, Gallery.image_url(key)}

            {:error, reason} ->
              Logger.warning("inline image store failed for #{filename}: #{inspect(reason)}")
              {:ok, nil}
          end
        end)

      socket = assign(socket, :images, post_images(post))

      if url do
        {:noreply,
         push_event(socket, "insert_image", %{url: url, alt: "", name: filename, token: token})}
      else
        {:noreply, put_flash(socket, :error, "Couldn't add #{filename} — not a supported image.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp split_upload_token(client_name) do
    case Regex.run(~r/^([0-9a-f]{6})--(.+)$/, client_name) do
      [_, token, filename] -> {token, filename}
      _ -> {nil, client_name}
    end
  end

  defp rejected_summary(rejected) do
    Enum.map_join(rejected, ", ", fn item ->
      "#{item["name"]} (#{rejection_reason(item["reason"])})"
    end)
  end

  defp rejection_reason("type"), do: "unsupported type"

  defp rejection_reason("size"),
    do: "larger than #{div(@upload_max_file_size, 1_000_000)}MB"

  defp rejection_reason(_), do: "too many files at once"

  defp upload_error_message(:too_large), do: "file too large"
  defp upload_error_message(:not_accepted), do: "unsupported file type"
  defp upload_error_message(:too_many_files), do: "too many files"
  defp upload_error_message(other), do: to_string(other)

  defp upload_accept, do: @upload_accept
  defp upload_max_entries, do: @upload_max_entries
  defp upload_max_file_size, do: @upload_max_file_size

  defp ensure_post(%{assigns: %{post: %Post{id: nil}}} = socket) do
    case Blog.create_post(backfill_new(%{})) do
      {:ok, post} ->
        PublicationNotifier.notify_change(nil, post)

        socket
        |> assign(:post, post)
        |> assign(:published_at, post.published_at)
        |> assign(:editor_post_id, post.id)
        |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")

      {:error, _changeset} ->
        socket
    end
  end

  defp ensure_post(socket), do: socket

  defp attach_image(%Post{id: nil}, _key, _original_filename), do: :ok

  defp attach_image(%Post{} = post, key, original_filename) do
    Blog.attach_image(post, key, original_filename)
    :ok
  end

  defp post_images(%Post{id: nil}), do: []
  defp post_images(%Post{} = post), do: Blog.list_images(post)

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    post = %Post{}

    socket
    |> sync_editor_key(nil)
    |> assign(:page_title, "New post")
    |> assign(:post, post)
    |> assign(:images, post_images(post))
    |> assign(:published_at, nil)
    |> assign(:slug_locked, false)
    |> assign(:slug_auto, "")
    |> assign(:excerpt_locked, false)
    |> assign(:excerpt_auto, "")
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> sync_editor_key(post.id)
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:images, post_images(post))
    |> assign(:published_at, post.published_at)
    |> assign(:slug_locked, slug_locked?(post))
    |> assign(:slug_auto, post.slug)
    |> assign(:excerpt_locked, excerpt_locked?(post))
    |> assign(:excerpt_auto, post.excerpt || "")
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  # The body editor's DOM is phx-update="ignore", so a same-module patch to a
  # DIFFERENT post would leave the previous post's content in CodeMirror.
  # Changing the key (and with it every id in the region) forces morphdom to
  # rebuild it; the key survives the /new -> /:id/edit patch of one editing
  # session because ensure_post/persist_autosave pre-assign the new post id.
  defp sync_editor_key(socket, post_id) do
    case socket.assigns.editor_post_id do
      :unset ->
        assign(socket, :editor_post_id, post_id)

      ^post_id ->
        socket

      _changed ->
        socket |> assign(:editor_key, new_editor_key()) |> assign(:editor_post_id, post_id)
    end
  end

  defp new_editor_key, do: "ed#{System.unique_integer([:positive])}"

  # Published posts lock the slug so existing links/SEO don't break.
  defp slug_locked?(post) do
    not is_nil(post.published_at) or post.slug != Newton.Slug.slugify(post.title)
  end

  defp excerpt_locked?(post) do
    (post.excerpt || "") != Newton.Markdown.excerpt(post.body_markdown || "")
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    {:noreply, apply_validate(socket, params)}
  end

  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "published_at", socket.assigns.published_at)
    save(socket, socket.assigns.post, params)
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
    open? = !socket.assigns.drawer_open
    socket = assign(socket, :drawer_open, open?)
    {:noreply, if(open?, do: put_card_preview(socket), else: socket)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, false)}
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
    {:noreply, set_published(socket, DateTime.truncate(DateTime.utc_now(), :second))}
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
    {:noreply, put_flash(socket, :error, "Not uploaded: #{rejected_summary(rejected)}")}
  end

  def handle_event("conflict_load_latest", _params, socket) do
    case Blog.get_post(socket.assigns.post.id) do
      nil ->
        {:noreply, deleted_elsewhere(socket)}

      post ->
        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:published_at, post.published_at)
         |> assign(:images, post_images(post))
         |> assign(:slug_locked, slug_locked?(post))
         |> assign(:slug_auto, post.slug)
         |> assign(:excerpt_locked, excerpt_locked?(post))
         |> assign(:excerpt_auto, post.excerpt || "")
         |> assign(:save_state, :saved)
         |> assign(:autosave_params, nil)
         |> assign(:form, to_form(Blog.change_post(post)))
         |> assign(:editor_key, new_editor_key())}
    end
  end

  def handle_event("conflict_keep_mine", _params, socket) do
    case Blog.get_post(socket.assigns.post.id) do
      nil ->
        {:noreply, deleted_elsewhere(socket)}

      fresh ->
        params = socket.assigns.autosave_params || %{}

        case Blog.update_post(fresh, never_blank_identity(params, fresh)) do
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
                assign(socket, :editor_key, new_editor_key())
              end

            {:noreply, socket}

          {:error, :stale} ->
            {:noreply, enter_conflict(socket)}

          {:error, _} ->
            {:noreply, assign(socket, :save_state, :error)}
        end
    end
  end

  def handle_event("recover", %{"post" => params}, socket) do
    if params["lock_version"] == to_string(socket.assigns.post.lock_version) do
      {:noreply,
       socket
       |> apply_validate(params)
       |> assign(:editor_key, new_editor_key())}
    else
      {:noreply,
       put_flash(socket, :info, "Updated in another window — showing the latest version.")}
    end
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
  def handle_info(:autosave, socket) do
    if is_nil(socket.assigns.published_at) and socket.assigns.autosave_params do
      persist_autosave(socket, socket.assigns.post, socket.assigns.autosave_params)
    else
      {:noreply, socket}
    end
  end

  defp persist_autosave(socket, %Post{id: nil}, params) do
    if content?(params) do
      case Blog.create_post(backfill_new(params)) do
        {:ok, post} ->
          PublicationNotifier.notify_change(nil, post)

          {:noreply,
           socket
           |> assign(:post, post)
           |> assign(:published_at, post.published_at)
           |> assign(:autosave_params, nil)
           |> assign(:autosave_timer, nil)
           |> assign(:save_state, :saved)
           |> assign(:editor_post_id, post.id)
           |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, assign(socket, :save_state, :saved)}
    end
  end

  defp persist_autosave(socket, %Post{} = post, params) do
    case Blog.update_post(post, never_blank_identity(params, post)) do
      {:ok, updated} ->
        PublicationNotifier.notify_change(post, updated)

        {:noreply,
         socket
         |> assign(:post, updated)
         |> assign(:autosave_params, nil)
         |> assign(:autosave_timer, nil)
         |> assign(:save_state, :saved)
         |> reoffer_identity(updated, params)}

      {:error, :stale} ->
        {:noreply, enter_conflict(socket)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :save_state, :error)}
    end
  end

  # A blank the author typed stays blank on screen; only untouched blanks
  # (LiveView's _unused_ markers) get the persisted identity offered back.
  defp reoffer_identity(socket, post, params) do
    if Enum.all?(~w(title slug), &(unused?(params, &1) or not blank?(params[&1]))) do
      assign(socket, :form, to_form(Blog.change_post(post)))
    else
      socket
    end
  end

  defp unused?(params, key), do: Map.has_key?(params, "_unused_" <> key)

  # A derived field (slug, excerpt) locks only once the author edits it. The
  # author touched it when LiveView drops the field's _unused_ marker; the value
  # a browser submits for an untouched field can lag the derived value, so a bare
  # value comparison would lock it spuriously.
  defp field_edited?(params, key, auto), do: not unused?(params, key) and params[key] != auto

  defp content?(params) do
    not blank?(params["title"]) or not blank?(params["body_markdown"])
  end

  defp never_blank_identity(params, post) do
    params
    |> keep_existing("title", post.title)
    |> keep_existing("slug", post.slug)
  end

  defp keep_existing(params, key, existing) do
    if blank?(params[key]), do: Map.put(params, key, existing), else: params
  end

  defp backfill_new(params) do
    if blank?(params["title"]) do
      params
      |> Map.put("title", "Untitled post")
      |> Map.put("slug", Blog.next_untitled_slug())
    else
      params
    end
  end

  defp apply_validate(socket, params) do
    published? = not is_nil(socket.assigns.published_at)

    slug_locked =
      socket.assigns.slug_locked or published? or
        field_edited?(params, "slug", socket.assigns.slug_auto)

    excerpt_locked =
      socket.assigns.excerpt_locked or
        field_edited?(params, "excerpt", socket.assigns.excerpt_auto)

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        Newton.Slug.slugify(params["title"] || "")
      end)

    {params, excerpt_auto} =
      FormHelpers.autofill(params, "excerpt", excerpt_locked, socket.assigns.excerpt_auto, fn ->
        Newton.Markdown.excerpt(params["body_markdown"] || "")
      end)

    form =
      socket.assigns.post
      |> Blog.change_post(params)
      |> Map.put(:action, :validate)
      |> to_form()

    socket
    |> assign(:form, form)
    |> assign(:slug_locked, slug_locked)
    |> assign(:slug_auto, slug_auto)
    |> assign(:excerpt_locked, excerpt_locked)
    |> assign(:excerpt_auto, excerpt_auto)
    |> track_save_state(params, published?)
  end

  defp track_save_state(%{assigns: %{save_state: :conflict}} = socket, params, _published?) do
    assign(socket, :autosave_params, params)
  end

  defp track_save_state(socket, params, false), do: maybe_schedule_autosave(socket, params, true)

  defp track_save_state(socket, params, true) do
    state = if dirty?(socket.assigns.post, params), do: :unsaved, else: :saved
    assign(socket, :save_state, state)
  end

  defp dirty?(post, params) do
    params["title"] != post.title or
      params["slug"] != post.slug or
      (params["body_markdown"] || "") != (post.body_markdown || "") or
      (params["excerpt"] || "") != (post.excerpt || "")
  end

  defp maybe_schedule_autosave(socket, params, true) do
    socket
    |> assign(:autosave_params, params)
    |> assign(:save_state, :unsaved)
    |> reschedule_autosave_timer()
  end

  defp reschedule_autosave_timer(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)
    assign(socket, :autosave_timer, Process.send_after(self(), :autosave, @autosave_debounce_ms))
  end

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

  defp enter_conflict(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:save_state, :conflict)
  end

  # Render the social card from the current form state (works for drafts/unsaved
  # edits, unlike the published-only public endpoint) and stash it as a data URI.
  defp put_card_preview(socket) do
    changeset = socket.assigns.form.source
    title = Ecto.Changeset.get_field(changeset, :title)

    attrs = %{
      title: if(title in [nil, ""], do: "Untitled post", else: title),
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
        |> enter_conflict()

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
  end

  defp save(socket, %Post{id: nil}, params) do
    case Blog.create_post(backfill_new(params)) do
      {:ok, post} ->
        PublicationNotifier.notify_change(nil, post)

        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
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
        {:noreply, socket |> assign(:autosave_params, params) |> enter_conflict()}

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

        <div id={"body-editor-#{@editor_key}"} phx-update="ignore">
          <textarea id={"post-body-markdown-#{@editor_key}"} name="post[body_markdown]" class="hidden"><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:body_markdown].value) %></textarea>
          <div
            id={"markdown-editor-#{@editor_key}"}
            phx-hook="MarkdownEditor"
            data-input-id={"post-body-markdown-#{@editor_key}"}
            data-upload-accept={Enum.join(upload_accept(), ",")}
            data-upload-max-entries={upload_max_entries()}
            data-upload-max-file-size={upload_max_file_size()}
            class="overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-surface)"
          >
            <div
              data-editor-skeleton
              aria-hidden="true"
              class="flex min-h-[24rem] flex-col gap-5 px-[1.75rem] py-[1.5rem] motion-safe:animate-pulse"
            >
              <div class="h-4 w-1/3 rounded bg-(--admin-border)"></div>
              <div class="h-4 w-full rounded bg-(--admin-border)"></div>
              <div class="h-4 w-5/6 rounded bg-(--admin-border)"></div>
              <div class="h-4 w-2/3 rounded bg-(--admin-border)"></div>
            </div>
          </div>
        </div>

        <.live_file_input upload={@uploads.inline_images} class="sr-only" />
        <p
          :for={err <- upload_errors(@uploads.inline_images)}
          class="mt-2 text-[0.78rem] text-red-400"
        >
          Upload failed: {upload_error_message(err)}
        </p>
        <%= for entry <- @uploads.inline_images.entries,
                err <- upload_errors(@uploads.inline_images, entry) do %>
          <p class="mt-2 text-[0.78rem] text-red-400">
            {entry.client_name}: {upload_error_message(err)}
          </p>
        <% end %>

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
            <img src={Gallery.image_url(image.key)} alt="" class="h-24 w-full rounded object-cover" />
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

        <div :if={is_nil(@published_at)} class="border-t border-(--admin-border) pt-3">
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
