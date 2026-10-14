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

  alias NewtonWeb.Admin.DraftEditor.Config
  alias NewtonWeb.Admin.FormHelpers

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
