defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :drawer_open, false)}
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
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    params = maybe_autofill_slug(params)

    form =
      socket.assigns.post
      |> Blog.change_post(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"post" => params}, socket) do
    params = Map.put(params, "published_at", socket.assigns.published_at)
    save(socket, socket.assigns.post, params)
  end

  def handle_event("toggle_drawer", _params, socket) do
    {:noreply, assign(socket, :drawer_open, !socket.assigns.drawer_open)}
  end

  def handle_event("publish_now", _params, socket) do
    {:noreply, assign(socket, :published_at, DateTime.truncate(DateTime.utc_now(), :second))}
  end

  def handle_event("unpublish", _params, socket) do
    {:noreply, assign(socket, :published_at, nil)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> push_navigate(to: ~p"/admin/posts")}
  end

  # Auto-fill the slug from the title only while the slug field is still blank,
  # so manual slug edits are never clobbered.
  defp maybe_autofill_slug(%{"slug" => slug} = params) when slug != "" do
    params
  end

  defp maybe_autofill_slug(%{"title" => title} = params) do
    Map.put(params, "slug", Newton.Slug.slugify(title))
  end

  defp maybe_autofill_slug(params), do: params

  defp save(socket, %Post{id: nil}, params) do
    case Blog.create_post(params) do
      {:ok, post} ->
        # Stay in the editor: patch to the new post's edit URL so subsequent
        # saves update it and a refresh works.
        {:noreply,
         socket
         |> put_flash(:info, "Post created")
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
         |> assign(:form, to_form(Blog.change_post(post)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:posts}>
      <.form for={@form} id="post-form" phx-submit="save" phx-change="validate">
        <div class="mb-4 flex items-center gap-3">
          <.link
            navigate={~p"/admin/posts"}
            class="text-[0.8rem] text-(--admin-text-subtle) no-underline hover:text-(--admin-text)"
          >
            ← Posts
          </.link>
          <div class="flex-1"></div>
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
            class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.8rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Save
          </button>
        </div>

        <.input
          field={@form[:title]}
          type="text"
          placeholder="Title"
          class="mb-2 w-full border-none bg-transparent text-2xl font-semibold text-(--admin-text) focus:outline-none"
        />

        <.input
          field={@form[:slug]}
          type="text"
          placeholder="slug"
          class="mb-4 w-full border-none bg-transparent font-mono text-[0.8rem] text-(--admin-text-subtle) focus:outline-none"
        />

        <.input
          field={@form[:body_markdown]}
          type="textarea"
          placeholder="Write your post in markdown…"
          rows="22"
          class="w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-4 font-mono text-[0.9rem] text-(--admin-text) focus:outline-none"
        />

        <.input
          field={@form[:excerpt]}
          type="textarea"
          label="Excerpt (optional — auto-derived from the body when blank)"
          rows="2"
          class="mt-4 w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-3 text-[0.85rem] text-(--admin-text) focus:outline-none"
        />
      </.form>

      <div
        id="publish-drawer"
        class={[
          "fixed inset-y-0 right-0 z-20 flex w-80 flex-col gap-4 border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl transition-transform",
          @drawer_open && "translate-x-0",
          !@drawer_open && "translate-x-full"
        ]}
      >
        <div class="flex items-center justify-between">
          <span class="text-[0.9rem] font-semibold">Publish</span>
          <button
            type="button"
            phx-click="toggle_drawer"
            aria-label="Close"
            class="text-(--admin-text-subtle) hover:text-(--admin-text)"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>

        <div class="text-[0.78rem] text-(--admin-text-muted)">
          Status:
          <span class="font-medium text-(--admin-text)">{Blog.publish_status(@published_at)}</span>
        </div>

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

        <button
          :if={@post.id}
          type="button"
          phx-click="delete"
          data-confirm="Delete this post permanently?"
          class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
        >
          Delete post
        </button>
      </div>
    </Layouts.admin>
    """
  end
end
