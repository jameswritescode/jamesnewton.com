defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias Newton.SocialCard
  alias Newton.Storage
  alias NewtonWeb.Admin.Autosave
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.InlineImageUpload
  alias NewtonWeb.Admin.Layouts
  alias NewtonWeb.PublicationNotifier

  # Autosave writes whatever it buffered without the publish-state scrubbing the
  # explicit "save" handler does, so only content fields are buffered. The
  # `_unused_` markers ride along because reoffer_identity/3 reads them to tell
  # an untouched blank from one the author cleared. `published_at` is set from
  # socket assigns, never from the client.
  @autosave_fields ~w(title slug excerpt body_markdown)
  @autosave_keys Autosave.keys(@autosave_fields)
  @untitled_title "Untitled post"
  @untitled_slug_prefix "untitled-post"

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
     |> InlineImageUpload.allow(progress: &handle_inline_upload/3)}
  end

  defp handle_inline_upload(:inline_images, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_inline_upload(:inline_images, entry, socket) do
    {:noreply, socket} =
      InlineImageUpload.handle_progress(entry, socket, %{
        ensure: &ensure_post/1,
        attach: &attach_image/3
      })

    {:noreply, assign(socket, :images, post_images(socket.assigns.post))}
  end

  defp ensure_post(%{assigns: %{post: %Post{id: nil}}} = socket) do
    case Blog.create_post(backfill_new(staged_content(socket))) do
      {:ok, post} ->
        PublicationNotifier.notify_change(nil, post)

        socket =
          socket
          |> cancel_autosave()
          |> assign(:editor_post_id, post.id)
          |> assign_post(post, "Edit post")
          |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")

        {socket, post}

      {:error, changeset} ->
        {creation_failed(socket, changeset), socket.assigns.post}
    end
  end

  defp ensure_post(socket), do: {socket, socket.assigns.post}

  defp staged_content(socket) do
    (socket.assigns.autosave_params || socket.assigns.form.source.params || %{})
    |> Map.take(@autosave_fields)
  end

  defp cancel_autosave(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:autosave_params, nil)
  end

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

  defp apply_action(socket, :new, _params), do: assign_post(socket, %Post{}, "New post")

  defp apply_action(socket, :edit, %{"id" => id}),
    do: assign_post(socket, Blog.get_post!(id), "Edit post")

  defp assign_post(socket, %Post{} = post, page_title) do
    socket
    |> sync_editor_key(post.id)
    |> assign(:page_title, page_title)
    |> assign(:post, post)
    |> assign(:images, post_images(post))
    |> assign(:published_at, post.published_at)
    |> assign(:slug_locked, slug_locked?(post))
    |> assign(:slug_auto, post.slug || "")
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
  defp slug_locked?(%Post{id: nil}), do: false

  defp slug_locked?(post) do
    not is_nil(post.published_at) or
      (post.slug != Newton.Slug.slugify(post.title) and
         not FormHelpers.placeholder_identity?(post, @untitled_title, @untitled_slug_prefix))
  end

  defp excerpt_locked?(post) do
    not blank?(post.excerpt) and
      post.excerpt != Newton.Markdown.excerpt(post.body_markdown || "")
  end

  @impl true
  def handle_event("validate", %{"post" => params} = payload, socket) do
    {:noreply, apply_validate(socket, params, payload["_target"])}
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
    {:noreply,
     put_flash(socket, :error, "Not uploaded: #{InlineImageUpload.rejected_summary(rejected)}")}
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
       |> apply_validate(params, nil)
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
           |> assign(:autosave_timer, nil)
           |> assign(:editor_post_id, post.id)
           |> assign_post(post, "Edit post")
           |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

        {:error, changeset} ->
          {:noreply, creation_failed(socket, changeset)}
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
    if Enum.all?(~w(title slug), &(FormHelpers.unused?(params, &1) or not blank?(params[&1]))) do
      assign(socket, :form, to_form(Blog.change_post(post)))
    else
      socket
    end
  end

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
      |> Map.put("title", @untitled_title)
      |> Map.put("slug", Blog.next_untitled_slug())
    else
      keep_existing(params, "slug", Newton.Slug.slugify(params["title"]))
    end
  end

  defp creation_failed(socket, changeset) do
    socket
    |> assign(:form, FormHelpers.failed_create_form(changeset))
    |> assign(:save_state, :error)
  end

  defp apply_validate(socket, params, target) do
    params = FormHelpers.keep_persisted_identity(params, socket.assigns.post)
    incoming = params
    published? = not is_nil(socket.assigns.published_at)

    slug_locked =
      FormHelpers.slug_locked?(
        params,
        socket.assigns.slug_locked,
        socket.assigns.slug_auto,
        published?,
        target
      )

    excerpt_locked =
      FormHelpers.derived_locked?(
        params,
        "excerpt",
        socket.assigns.excerpt_locked,
        socket.assigns.excerpt_auto,
        target
      )

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        FormHelpers.title_slug(params["title"], @untitled_title, socket.assigns.slug_auto)
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
    |> FormHelpers.push_derived_refills(form, incoming, params, ~w(slug excerpt)a)
    |> assign(:slug_locked, slug_locked)
    |> assign(:slug_auto, slug_auto)
    |> assign(:excerpt_locked, excerpt_locked)
    |> assign(:excerpt_auto, excerpt_auto)
    |> track_save_state(params, published?)
  end

  defp track_save_state(%{assigns: %{save_state: :conflict}} = socket, params, _published?) do
    assign(socket, :autosave_params, Autosave.content_params(params, @autosave_keys))
  end

  defp track_save_state(socket, params, false), do: maybe_schedule_autosave(socket, params, true)

  defp track_save_state(socket, params, true) do
    dirty? = Autosave.dirty?(params, socket.assigns.post, @autosave_fields)
    assign(socket, :save_state, if(dirty?, do: :unsaved, else: :saved))
  end

  defp maybe_schedule_autosave(socket, params, true) do
    socket
    |> assign(:autosave_params, Autosave.content_params(params, @autosave_keys))
    |> assign(:save_state, :unsaved)
    |> reschedule_autosave_timer()
  end

  defp reschedule_autosave_timer(socket) do
    assign(socket, :autosave_timer, Autosave.schedule(socket.assigns.autosave_timer))
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
    attrs =
      (socket.assigns.form.source.params || %{})
      |> Map.take(@autosave_fields)
      |> backfill_new()
      |> Map.put("published_at", DateTime.truncate(DateTime.utc_now(), :second))

    case Blog.create_post(attrs) do
      {:ok, post} ->
        PublicationNotifier.notify_change(nil, post)

        socket
        |> assign(:post, post)
        |> assign(:published_at, post.published_at)
        |> assign(:slug_locked, slug_locked?(post))
        |> assign(:autosave_params, nil)
        |> assign(:save_state, :saved)
        |> assign(:editor_post_id, post.id)
        |> put_flash(:info, "Post published")
        |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")

      {:error, changeset} ->
        assign(socket, :form, FormHelpers.failed_create_form(changeset))
    end
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
        {:noreply, assign(socket, :form, FormHelpers.failed_create_form(changeset))}
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
