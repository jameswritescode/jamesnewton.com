defmodule NewtonWeb.Admin.PostLive.Editor do
  use NewtonWeb, :live_view

  alias Newton.Blog
  alias Newton.Blog.Post
  alias NewtonWeb.Admin.Layouts

  @impl true
  def mount(params, _session, socket) do
    {:ok, load(socket, socket.assigns.live_action, params)}
  end

  defp load(socket, :new, _params) do
    post = %Post{}

    socket
    |> assign(:page_title, "New post")
    |> assign(:post, post)
    |> assign(:published_at, nil)
    |> assign(:drawer_open, false)
    |> assign(:form, to_form(Blog.change_post(post)))
  end

  defp load(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit post")
    |> assign(:post, post)
    |> assign(:published_at, post.published_at)
    |> assign(:drawer_open, false)
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
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post created")
         |> push_navigate(to: ~p"/admin/posts")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, %Post{} = post, params) do
    case Blog.update_post(post, params) do
      {:ok, _post} ->
        {:noreply,
         socket
         |> put_flash(:info, "Post saved")
         |> push_navigate(to: ~p"/admin/posts")}

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
          rows="24"
          class="w-full rounded-lg border border-(--admin-border) bg-(--admin-surface) p-4 font-mono text-[0.9rem] text-(--admin-text) focus:outline-none"
        />
      </.form>
    </Layouts.admin>
    """
  end
end
