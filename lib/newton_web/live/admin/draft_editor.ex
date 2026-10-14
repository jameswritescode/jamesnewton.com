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
  import Phoenix.Component, only: [assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias NewtonWeb.Admin.Autosave
  alias NewtonWeb.Admin.DraftEditor.Config
  alias NewtonWeb.Admin.FormHelpers
  alias NewtonWeb.Admin.InlineImageUpload

  @type socket :: Phoenix.LiveView.Socket.t()

  @doc "Assign the draft-lifecycle state a freshly mounted editor starts from."
  @spec mount(socket()) :: socket()
  def mount(socket) do
    socket
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:autosave_timer, nil)
    |> assign(:editor_key, new_editor_key())
    |> assign(:editor_record_id, :unset)
  end

  @doc "Load `record` into the editor: its form, lock state, and a clean save state."
  @spec assign_record(socket(), Config.t(), Config.draft(), String.t()) :: socket()
  def assign_record(socket, %Config{} = config, record, page_title) do
    socket
    |> sync_editor_key(record.id)
    |> assign(:page_title, page_title)
    |> assign(config.record, record)
    |> assign_locks(config, record)
    |> assign(:save_state, :saved)
    |> assign(:autosave_params, nil)
    |> assign(:form, to_form(config.change.(record, %{})))
  end

  # The body editor's DOM is phx-update="ignore", so a same-module patch to a
  # DIFFERENT record would leave the previous record's content in CodeMirror.
  # Changing the key (and with it every id in the region) forces morphdom to
  # rebuild it; the key survives the /new -> /:id/edit patch of one editing
  # session because every create claims the new record's id first.
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

  @doc "Create a record from staged `params`, backfilling its identity, and notify the change."
  @spec create(socket(), Config.t(), map()) ::
          {:ok, Config.draft()} | {:error, Ecto.Changeset.t()}
  def create(socket, %Config{} = config, params) do
    with {:ok, record} <- config.create.(backfill_new(socket, config, params)) do
      config.notify.(nil, record)
      {:ok, record}
    end
  end

  @doc "Mark `record` as the one this editing session created, so the editor keeps its key."
  @spec claim_record(socket(), Config.draft()) :: socket()
  def claim_record(socket, record), do: assign(socket, :editor_record_id, record.id)

  defp created(socket, config, record) do
    socket
    |> claim_record(record)
    |> config.load_saved.(record)
    |> push_patch(to: config.edit_path.(record))
  end

  @doc """
  Write the buffered autosave params, if any, of a draft: create the record
  once there is content, otherwise update it, entering a conflict when another
  window saved first.
  """
  @spec autosave(socket(), Config.t()) :: socket()
  def autosave(socket, %Config{} = config) do
    params = socket.assigns.autosave_params

    if not config.editing_published?.(socket.assigns) and params do
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
          |> created(config, record)

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
        |> assign(config.record, updated)
        |> assign(:autosave_params, nil)
        |> assign(:autosave_timer, nil)
        |> assign(:save_state, :saved)

      {:error, :stale} ->
        enter_conflict(socket)

      {:error, _changeset} ->
        assign(socket, :save_state, :error)
    end
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
              |> created(config, record)

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

  defp creation_failed(socket, changeset) do
    socket
    |> assign(:form, FormHelpers.failed_create_form(changeset))
    |> assign(:save_state, :error)
  end

  @doc "Stop autosaving and show the conflict banner: another window saved first."
  @spec enter_conflict(socket()) :: socket()
  def enter_conflict(socket) do
    if ref = socket.assigns.autosave_timer, do: Process.cancel_timer(ref)

    socket
    |> assign(:autosave_timer, nil)
    |> assign(:save_state, :conflict)
  end

  @doc "Assign the slug and derived-field lock state of a freshly loaded `record`."
  @spec assign_locks(Phoenix.LiveView.Socket.t(), Config.t(), Config.draft()) ::
          Phoenix.LiveView.Socket.t()
  def assign_locks(socket, %Config{} = config, record) do
    socket
    |> assign(:slug_locked, loaded_slug_locked?(config, record))
    |> assign(:slug_auto, record.slug || "")
    |> assign(:derived_locked, loaded_derived_locked?(config, record))
    |> assign(:derived_auto, Map.fetch!(record, config.derived_field) || "")
  end

  @doc """
  Apply a form change: repair stale blank identity values, decide which derived
  fields the author has taken over (`target` is the change's `"_target"`, nil
  for a recovered form), autofill the rest, push refills the browser would
  otherwise miss, and track the save state.
  """
  @spec apply_validate(Phoenix.LiveView.Socket.t(), Config.t(), map(), [String.t()] | nil) ::
          Phoenix.LiveView.Socket.t()
  def apply_validate(socket, %Config{} = config, incoming, target) do
    record = record(socket, config)
    derived = Atom.to_string(config.derived_field)
    params = FormHelpers.keep_persisted_identity(incoming, record)
    published? = config.editing_published?.(socket.assigns)

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

  defp record(socket, %Config{record: key}), do: Map.fetch!(socket.assigns, key)

  @doc "Does `params` carry a title or a body, enough to create a record from?"
  @spec content?(map()) :: boolean()
  def content?(params) do
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

  @doc "Fill in the identity a create of staged `params` needs (see `FormHelpers.backfill_identity/4`)."
  @spec backfill_new(Phoenix.LiveView.Socket.t(), Config.t(), map()) :: map()
  def backfill_new(socket, %Config{} = config, params) do
    FormHelpers.backfill_identity(
      params,
      socket.assigns.slug_locked,
      config.placeholder_title,
      config.next_untitled_slug
    )
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

  @doc "Does a loaded `record` carry a derived field the author wrote rather than its body's excerpt?"
  @spec loaded_derived_locked?(Config.t(), Config.draft()) :: boolean()
  def loaded_derived_locked?(_config, %{id: nil}), do: false

  def loaded_derived_locked?(%Config{derived_field: field}, record) do
    value = Map.fetch!(record, field)
    not blank?(value) and value != Newton.Markdown.excerpt(record.body_markdown || "")
  end
end
