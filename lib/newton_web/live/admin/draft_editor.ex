defmodule NewtonWeb.Admin.DraftEditor do
  @moduledoc """
  The draft lifecycle shared by the post and page editors: deriving the slug
  and body-derived field until the author takes them over, autosaving drafts,
  creating the record on first content, and entering a conflict when another
  window saved first. Each editor describes its record with a
  `NewtonWeb.Admin.DraftEditor.Config` and keeps its own event handlers,
  delegating the shared ones here.
  """

  import NewtonWeb.Helpers, only: [blank?: 1]
  import Phoenix.Component, only: [assign: 3, to_form: 1, update: 3]
  import Phoenix.LiveView, only: [push_patch: 2, put_flash: 3]

  alias NewtonWeb.Admin.Autosave
  alias NewtonWeb.Admin.DraftEditor.Config
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.InlineImageUpload

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc "Assign the draft-lifecycle state a freshly mounted editor starts from."
  @spec mount(socket()) :: socket()
  def mount(socket) do
    socket
    |> assign(:drawer_open, false)
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:autosave_timer, nil)
    |> assign(:editor_key, new_editor_key())
    |> assign(:editor_record_id, :unset)
  end

  @doc """
  Load `record` into the editor: its form, a clean save state, and its lock
  state. The slug stays locked when it is published or one the author chose,
  and the derived field when it holds text the author wrote rather than the
  body's excerpt.
  """
  @spec assign_record(socket(), Config.t(), Config.draft(), String.t()) :: socket()
  def assign_record(socket, %Config{} = config, record, page_title) do
    socket
    |> sync_editor_key(record.id)
    |> assign(:page_title, page_title)
    |> assign(config.record_assign, record)
    |> assign_locks(config, record)
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(config.change.(record, %{})))
  end

  # The body editor's DOM is phx-update="ignore", so a same-module patch to a
  # DIFFERENT record would leave the previous record's content in CodeMirror.
  # Changing the key (and with it every id in the region) forces morphdom to
  # rebuild it; the key survives the /new -> /:id/edit patch of one editing
  # session because every create (autosave, first image, Save, Publish) claims
  # the new record's id before patching to it.
  defp sync_editor_key(socket, record_id) do
    case socket.assigns.editor_record_id do
      :unset ->
        assign(socket, :editor_record_id, record_id)

      ^record_id ->
        socket

      _changed ->
        socket |> assign(:editor_key, new_editor_key()) |> assign(:editor_record_id, record_id)
    end
  end

  @doc "A fresh key for the body editor region, forcing its DOM to rebuild."
  @spec new_editor_key() :: String.t()
  def new_editor_key, do: "ed#{System.unique_integer([:positive])}"

  defp assign_locks(socket, %Config{} = config, record) do
    socket
    |> assign(:slug_locked, loaded_slug_locked?(config, record))
    |> assign(:slug_auto, record.slug || "")
    |> assign(:derived_locked, loaded_derived_locked?(config, record))
    |> assign(:derived_auto, Map.fetch!(record, config.derived_field) || "")
  end

  @doc """
  Does a loaded `record` keep its slug rather than follow its title? A
  published record does, so existing links don't break, and so does a slug the
  author chose, unlike the placeholder identity of an untitled draft.
  """
  @spec loaded_slug_locked?(Config.t(), Config.draft()) :: boolean()
  def loaded_slug_locked?(_config, %{id: nil}), do: false

  def loaded_slug_locked?(%Config{} = config, record) do
    config.published?.(record) or
      (record.slug != Newton.Slug.slugify(record.title || "") and
         not FormHelpers.placeholder_identity?(
           record,
           config.placeholder_title,
           config.untitled_slug_prefix
         ))
  end

  defp loaded_derived_locked?(_config, %{id: nil}), do: false

  defp loaded_derived_locked?(%Config{derived_field: field}, record) do
    value = Map.fetch!(record, field)
    not blank?(value) and value != Newton.Markdown.excerpt(record.body_markdown || "")
  end

  @doc """
  Apply a form change: repair stale blank identity values, decide which derived
  fields the author has taken over (`target` is the change's `"_target"`, nil
  for a recovered form), autofill the rest, push refills the browser would
  otherwise miss, and track the save state.
  """
  @spec apply_validate(socket(), Config.t(), map(), [String.t()] | nil) ::
          socket()
  def apply_validate(socket, %Config{} = config, incoming, target) do
    record = record(socket, config)
    derived = Atom.to_string(config.derived_field)
    params = FormHelpers.keep_persisted_identity(incoming, record)
    published? = config.published?.(record)

    slug_locked =
      FormHelpers.slug_locked?(
        params,
        socket.assigns.slug_locked,
        socket.assigns.slug_auto,
        published?,
        target
      )

    derived_locked =
      FormHelpers.derived_locked?(
        params,
        derived,
        socket.assigns.derived_locked,
        socket.assigns.derived_auto,
        target
      )

    {params, slug_auto} =
      FormHelpers.autofill(params, "slug", slug_locked, socket.assigns.slug_auto, fn ->
        FormHelpers.title_slug(
          params["title"],
          config.placeholder_title,
          record,
          socket.assigns.slug_auto
        )
      end)

    {params, derived_auto} =
      FormHelpers.autofill(params, derived, derived_locked, socket.assigns.derived_auto, fn ->
        Newton.Markdown.excerpt(params["body_markdown"] || "")
      end)

    form =
      record
      |> config.change.(params)
      |> Map.put(:action, :validate)
      |> to_form()

    socket
    |> assign(:form, form)
    |> FormHelpers.push_derived_refills(form, incoming, params, [
      :title,
      :slug,
      config.derived_field
    ])
    |> assign(:slug_locked, slug_locked)
    |> assign(:slug_auto, slug_auto)
    |> assign(:derived_locked, derived_locked)
    |> assign(:derived_auto, derived_auto)
    |> track_save_state(config, params, published?)
  end

  defp track_save_state(%{assigns: %{save_state: :conflict}} = socket, config, params, _pub?) do
    assign(socket, :autosave_params, autosave_params(config, params))
  end

  defp track_save_state(socket, config, params, true) do
    dirty? = Autosave.dirty?(params, record(socket, config), config.autosave_fields)
    assign(socket, :save_state, if(dirty?, do: :unsaved, else: :saved))
  end

  defp track_save_state(socket, config, params, false) do
    socket
    |> assign(:autosave_params, autosave_params(config, params))
    |> assign(:save_state, :unsaved)
    |> assign(:autosave_timer, Autosave.schedule(socket.assigns.autosave_timer))
  end

  defp autosave_params(config, params) do
    Autosave.content_params(params, Autosave.keys(config.autosave_fields))
  end

  @doc """
  Save a field's blur right away instead of waiting out the debounce. A body
  carried in `params` (the editor hook's flush) joins the buffered params. Does
  nothing during a conflict.
  """
  @spec autosave_now(socket(), map()) :: socket()
  def autosave_now(%{assigns: %{save_state: :conflict}} = socket, _params), do: socket

  def autosave_now(socket, params) do
    socket =
      case params do
        %{"body_markdown" => body} ->
          update(socket, :autosave_params, &Map.put(&1 || %{}, "body_markdown", body))

        _ ->
          socket
      end

    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)
    send(self(), :autosave)
    assign(socket, :autosave_timer, nil)
  end

  @doc """
  Write the buffered autosave params, if any, of a draft: create the record
  once there is content, otherwise update it, entering a conflict when another
  window saved first.
  """
  @spec autosave(socket(), Config.t()) :: socket()
  def autosave(socket, %Config{} = config) do
    params = socket.assigns.autosave_params

    if not config.published?.(record(socket, config)) and params do
      persist_autosave(socket, config, record(socket, config), params)
    else
      socket
    end
  end

  defp persist_autosave(socket, config, %{id: nil}, params) do
    if content?(params) do
      case create(socket, config, params) do
        {:ok, record} ->
          socket
          |> assign(:autosave_timer, nil)
          |> after_create(config, record)

        {:error, changeset} ->
          creation_failed(socket, changeset)
      end
    else
      assign(socket, :save_state, :saved)
    end
  end

  defp persist_autosave(socket, config, record, params) do
    case config.update.(record, never_blank_identity(params, record)) do
      {:ok, updated} ->
        config.notify.(record, updated)

        socket
        |> assign(config.record_assign, updated)
        |> assign(:autosave_params, nil)
        |> assign(:autosave_timer, nil)
        |> assign(:save_state, :saved)

      {:error, :stale} ->
        enter_conflict(socket)

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
  end

  defp create(socket, %Config{} = config, params) do
    with {:ok, record} <- config.create.(backfill_new(socket, config, params)) do
      config.notify.(nil, record)
      {:ok, record}
    end
  end

  defp claim_record(socket, record), do: assign(socket, :editor_record_id, record.id)

  defp after_create(socket, config, record) do
    socket
    |> claim_record(record)
    |> config.load_saved.(record)
    |> push_patch(to: config.edit_path.(record))
  end

  defp creation_failed(socket, changeset) do
    socket
    |> assign(:form, FormHelpers.failed_create_form(changeset))
    |> assign(:save_state, :error)
  end

  @doc """
  Handle progress on an inline image upload, recording a finished one on the
  record's image ledger. The first image dropped into an unsaved record needs a
  row to hang the ledger entry on, so it creates the draft and moves to its
  edit URL.
  """
  @spec upload_progress(Phoenix.LiveView.UploadEntry.t(), socket(), Config.t()) ::
          {:noreply, socket()}
  def upload_progress(entry, socket, %Config{} = config) do
    InlineImageUpload.handle_progress(entry, socket, %{
      ensure: &ensure_record(&1, config),
      attach: &attach_image(config, &1, &2, &3)
    })
  end

  defp ensure_record(socket, config) do
    case record(socket, config) do
      %{id: nil} = unsaved ->
        case create(socket, config, staged_content(socket, config)) do
          {:ok, record} ->
            socket =
              socket
              |> cancel_autosave()
              |> after_create(config, record)

            {socket, record}

          {:error, changeset} ->
            {creation_failed(socket, changeset), unsaved}
        end

      record ->
        {socket, record}
    end
  end

  defp attach_image(_config, %{id: nil}, _key, _original_filename), do: :ok

  defp attach_image(config, record, key, original_filename) do
    config.attach_image.(record, key, original_filename)
    :ok
  end

  defp staged_content(socket, config) do
    (socket.assigns.autosave_params || socket.assigns.form.source.params || %{})
    |> Map.take(config.autosave_fields)
  end

  defp cancel_autosave(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:autosave_params, nil)
  end

  @doc "Flash the files the client-side upload hook refused."
  @spec upload_rejected(socket(), [map()]) :: socket()
  def upload_rejected(socket, rejected) do
    put_flash(socket, :error, "Not uploaded: #{InlineImageUpload.rejected_summary(rejected)}")
  end

  @doc "Stop autosaving and show the conflict banner: another window saved first."
  @spec enter_conflict(socket()) :: socket()
  def enter_conflict(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:save_state, :conflict)
  end

  @doc """
  Restore a form the client recovered after a reconnect, unless the record has
  moved on since: then the latest version stays and the author is told why.
  """
  @spec recover(socket(), Config.t(), map()) :: socket()
  def recover(socket, %Config{} = config, params) do
    if params["lock_version"] == to_string(record(socket, config).lock_version) do
      socket
      |> apply_validate(config, params, nil)
      |> assign(:editor_key, new_editor_key())
    else
      put_flash(socket, :info, "Updated in another window — showing the latest version.")
    end
  end

  @doc "Open the settings drawer if closed, close it if open."
  @spec toggle_drawer(socket()) :: socket()
  def toggle_drawer(socket), do: assign(socket, :drawer_open, !socket.assigns.drawer_open)

  @doc "Close the settings drawer."
  @spec close_drawer(socket()) :: socket()
  def close_drawer(socket), do: assign(socket, :drawer_open, false)

  @doc """
  Save a new record from the submitted `params`, then hand it to `on_saved`.
  Refuses, with a flash, when there is neither a title nor a body. An untitled
  record takes the placeholder title and the next untitled slug (see
  `FormHelpers.backfill_identity/4`), as every create here does.
  """
  @spec save_new(socket(), Config.t(), map(), (socket(), Config.draft() -> socket())) ::
          socket()
  def save_new(socket, %Config{} = config, params, on_saved) do
    require_content(socket, params, "saving", fn ->
      create_or_show_errors(socket, config, params, on_saved)
    end)
  end

  @doc """
  Create a new record published from the form's staged content, merged with
  `published_attrs`, then hand it to `on_published`. Refuses, with a flash, when
  there is neither a title nor a body.
  """
  @spec publish_new(socket(), Config.t(), map(), (socket(), Config.draft() -> socket())) ::
          socket()
  def publish_new(socket, %Config{} = config, published_attrs, on_published) do
    staged = Map.take(socket.assigns.form.source.params || %{}, config.autosave_fields)

    require_content(socket, staged, "publishing", fn ->
      create_or_show_errors(socket, config, Map.merge(staged, published_attrs), on_published)
    end)
  end

  defp require_content(socket, params, action, create) do
    if content?(params),
      do: create.(),
      else: put_flash(socket, :error, "Add a title or body before #{action}")
  end

  defp create_or_show_errors(socket, config, params, on_created) do
    case create(socket, config, params) do
      {:ok, record} -> socket |> claim_record(record) |> on_created.(record)
      {:error, changeset} -> assign(socket, :form, FormHelpers.failed_create_form(changeset))
    end
  end

  defp record(socket, %Config{record_assign: key}), do: Map.fetch!(socket.assigns, key)

  defp content?(params) do
    not blank?(params["title"]) or not blank?(params["body_markdown"])
  end

  @doc "Keep `record`'s title and slug wherever `params` carries them blank."
  @spec never_blank_identity(map(), Config.draft()) :: map()
  def never_blank_identity(params, record) do
    params
    |> keep_existing("title", record.title)
    |> keep_existing("slug", record.slug)
  end

  defp keep_existing(params, key, existing) do
    if blank?(params[key]), do: Map.put(params, key, existing), else: params
  end

  defp backfill_new(socket, %Config{} = config, params) do
    FormHelpers.backfill_identity(
      params,
      socket.assigns.slug_locked,
      config.placeholder_title,
      config.next_untitled_slug
    )
  end
end
