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

  alias NewtonWeb.Admin.Autosave
  alias NewtonWeb.Admin.DraftEditor.Config
  alias NewtonWeb.Admin.FormHelpers

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
