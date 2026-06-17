defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias NewtonWeb.Admin.Components
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.Layouts

  @autosave_debounce_ms 1500

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:drawer_open, false)
     |> assign(:save_state, :saved)
     |> assign(:autosave_params, nil)
     |> assign(:autosave_timer, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    post = %Post{}

    socket
    |> assign(:page_title, "New post")
    |> assign(:post, post)
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
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> assign(:slug_locked, slug_locked?(post))
    |> assign(:slug_auto, post.slug)
    |> assign(:excerpt_locked, excerpt_locked?(post))
    |> assign(:excerpt_auto, post.excerpt || "")
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  # Published posts lock the slug so existing links/SEO don't break.
  defp slug_locked?(post) do
    not is_nil(post.published_at) or post.slug != Newton.Slug.slugify(post.title)
  end

  defp excerpt_locked?(post) do
    (post.excerpt || "") != Newton.Markdown.excerpt(post.body_markdown || "")
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    published? = not is_nil(socket.assigns.published_at)

    slug_locked =
      socket.assigns.slug_locked or published? or params["slug"] != socket.assigns.slug_auto

    excerpt_locked =
      socket.assigns.excerpt_locked or params["excerpt"] != socket.assigns.excerpt_auto

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

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_locked, slug_locked)
     |> assign(:slug_auto, slug_auto)
     |> assign(:excerpt_locked, excerpt_locked)
     |> assign(:excerpt_auto, excerpt_auto)
     |> track_save_state(params, published?)}
  end

  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "published_at", socket.assigns.published_at)
    save(socket, socket.assigns.post, params)
  end

  def handle_event("autosave_now", _params, socket) do
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

  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> push_navigate(to: ~p"/admin/posts")}
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
          {:noreply,
           socket
           |> assign(:post, post)
           |> assign(:published_at, post.published_at)
           |> assign(:autosave_params, nil)
           |> assign(:autosave_timer, nil)
           |> assign(:save_state, :saved)
           |> push_patch(to: ~p"/admin/posts/#{post.id}/edit")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :save_state, :error)}
      end
    else
      {:noreply, assign(socket, :save_state, :saved)}
    end
  end

  defp persist_autosave(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, post} ->
        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:autosave_params, nil)
         |> assign(:autosave_timer, nil)
         |> assign(:save_state, :saved)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :save_state, :error)}
    end
  end

  defp content?(params) do
    String.trim(params["title"] || "") != "" or String.trim(params["body_markdown"] || "") != ""
  end

  defp backfill_new(params) do
    if String.trim(params["title"] || "") == "" do
      params
      |> Map.put("title", "Untitled post")
      |> Map.put("slug", Blog.next_untitled_slug())
    else
      params
    end
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

  defp save_state_label(:unsaved), do: "Unsaved changes…"
  defp save_state_label(:error), do: "Couldn't save"
  defp save_state_label(_), do: "Saved"

  # Drafts autosave: the Save button becomes the live indicator ("Saving…").
  defp saving?(published_at, save_state), do: is_nil(published_at) and save_state == :unsaved

  # Published posts show the text indicator (manual-save signal); drafts only show
  # it on error, since the button otherwise carries their state.
  defp show_save_text?(published_at, save_state) do
    (not is_nil(published_at) and save_state != :saved) or
      (is_nil(published_at) and save_state == :error)
  end

  # Publishing toggles publication state on the saved post; content edits in the
  # form are left untouched.
  defp set_published(socket, published_at) do
    {:ok, post} = Blog.update_post(socket.assigns.post, %{"published_at" => published_at})

    socket
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> put_flash(:info, if(post.published_at, do: "Post published", else: "Moved to draft"))
  end

  defp save(socket, %Post{id: nil}, params) do
    case Blog.create_post(backfill_new(params)) do
      {:ok, post} ->
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
      {:ok, post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> assign(:post, post)
         |> assign(:published_at, post.published_at)
         |> assign(:form, to_form(Blog.change_post(post)))
         |> assign(:save_state, :saved)
         |> assign(:autosave_params, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <.form for={@form} id="post-form" phx-submit="save" phx-change="validate">
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
          <button
            type="button"
            phx-click="toggle_drawer"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-text) hover:bg-(--admin-accent-soft)"
          >
            Settings
          </button>
          <button
            type="submit"
            disabled={saving?(@published_at, @save_state)}
            class="flex items-center gap-1.5 rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover) disabled:cursor-not-allowed disabled:opacity-70"
          >
            <span
              :if={saving?(@published_at, @save_state)}
              class="size-3 animate-spin rounded-full border-2 border-white/40 border-t-white"
            >
            </span>
            {if saving?(@published_at, @save_state), do: "Saving…", else: "Save"}
          </button>
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

        <div id="body-editor" phx-update="ignore">
          <textarea id="post_body_markdown" name="post[body_markdown]" class="hidden"><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:body_markdown].value) %></textarea>
          <div
            id="markdown-editor"
            phx-hook="MarkdownEditor"
            data-input-id="post_body_markdown"
            class="overflow-hidden rounded-lg border border-(--admin-border) bg-(--admin-surface)"
          >
          </div>
        </div>

        <.input
          field={@form[:excerpt]}
          type="textarea"
          label="Excerpt (auto-derived from the body until you edit it)"
          rows="2"
          class="mt-4 w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-3 text-[0.85rem] text-(--admin-text) focus:outline-none"
        />
      </.form>

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

        <div class="flex gap-2">
          <button
            :if={Blog.publish_status(@published_at) != :published}
            type="button"
            phx-click="publish_now"
            class="flex-1 rounded-md bg-(--admin-accent) px-2 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Publish now
          </button>
          <button
            :if={Blog.publish_status(@published_at) != :draft}
            type="button"
            phx-click="unpublish"
            class="flex-1 rounded-md border border-(--admin-border) px-2 py-1.5 text-[0.78rem] hover:bg-(--admin-accent-soft)"
          >
            Move to draft
          </button>
        </div>

        <div class="text-[0.78rem] text-(--admin-text-subtle)">
          Reading time: {@post.reading_time || "—"} min
        </div>

        <.link
          :if={@post.id}
          href={~p"/posts/#{@post.slug}"}
          target="_blank"
          class="text-[0.8rem] text-(--admin-accent) no-underline hover:underline"
        >
          View on site ↗
        </.link>

        <div class="flex-1"></div>

        <Components.delete_button
          :if={@post.id}
          event="delete"
          confirm="Delete this post permanently?"
        />
      </Components.drawer>
    </Layouts.admin>
    """
  end
end
