defmodule NewtonWeb.Admin.FormHelpers do
  @moduledoc "Shared helpers for admin LiveView forms."

  @doc """
  Derive a param field from another until the user takes it over. Returns
  `{params, new_auto}`: when locked, params and the previous auto value pass
  through unchanged; when unlocked, `derive` recomputes the value, writes it into
  params, and becomes the new auto baseline.
  """
  @spec autofill(map(), String.t(), boolean(), String.t(), (-> String.t())) ::
          {map(), String.t()}
  def autofill(params, _field, true, prev_auto, _derive), do: {params, prev_auto}

  def autofill(params, field, false, _prev_auto, derive) do
    value = derive.()
    {Map.put(params, field, value), value}
  end

  @doc "Did LiveView mark `key` as untouched in this submission?"
  @spec unused?(map(), String.t()) :: boolean()
  def unused?(params, key), do: Map.has_key?(params, "_unused_" <> key)

  @doc """
  Did the author edit a derived field (slug, excerpt, meta description) in this
  submission? Every change submits the whole form, carrying each field's current
  browser value, and a value can lag the derived one while the reply that
  updates it is still in flight. Only the input that triggered the change is
  news from the author, so when LiveView names that input (`target`, from
  `"_target"`) the field counts as edited only on its own events. Without a
  target, the field counts as edited once LiveView drops its `_unused_` marker.
  """
  @spec field_edited?(map(), String.t(), String.t(), [String.t()] | nil) :: boolean()
  def field_edited?(params, key, auto, nil), do: not unused?(params, key) and params[key] != auto

  def field_edited?(params, key, auto, target) when is_list(target),
    do: List.last(target) == key and params[key] != auto

  @doc """
  Does a derived field (slug, excerpt, meta description) stay the author's own
  rather than following its source? A value the author edited (see
  `field_edited?/4`) stays locked, but a blank one means "auto" and reverts to
  following the source: clearing the field is how the author hands it back, and
  a blank also arrives as a stale browser value after the form was reset, where
  locking it would leave the record with an empty field.
  """
  @spec derived_locked?(map(), String.t(), boolean(), String.t(), [String.t()] | nil) ::
          boolean()
  def derived_locked?(params, field, previously_locked?, auto, target) do
    (previously_locked? or field_edited?(params, field, auto, target)) and
      not blank?(params[field])
  end

  @doc """
  Does the slug stay the author's own rather than following the title? A
  published record keeps its slug so links don't break; a draft's slug follows
  `derived_locked?/5`.
  """
  @spec slug_locked?(map(), boolean(), String.t(), boolean(), [String.t()] | nil) :: boolean()
  def slug_locked?(params, previously_locked?, auto, published?, target) do
    published? or derived_locked?(params, "slug", previously_locked?, auto, target)
  end

  @doc """
  The slug a title derives. A blank or placeholder title has no slug of its
  own: a saved `record` keeps `current`, since slugifying the placeholder would
  collapse every untitled draft onto one slug, and an unsaved one yields a
  blank slug so its create generates one (see `backfill_identity/4`).
  """
  @spec title_slug(String.t() | nil, String.t(), map(), String.t()) :: String.t()
  def title_slug(title, placeholder_title, record, current) do
    cond do
      not untitled?(title, placeholder_title) -> Newton.Slug.slugify(title)
      Map.get(record, :id) -> current
      true -> ""
    end
  end

  @doc """
  Fill in the identity a create needs from staged `params`. An untitled draft
  takes `placeholder_title` and a slug from `next_placeholder_slug`, unless the
  author chose its slug (`slug_locked?`); a titled one with a blank slug takes
  its title's slug.
  """
  @spec backfill_identity(map(), boolean(), String.t(), (-> String.t())) :: map()
  def backfill_identity(params, slug_locked?, placeholder_title, next_placeholder_slug) do
    cond do
      untitled?(params["title"], placeholder_title) ->
        slug =
          if slug_locked? and not blank?(params["slug"]),
            do: params["slug"],
            else: next_placeholder_slug.()

        params
        |> Map.put("title", placeholder_title)
        |> Map.put("slug", slug)

      blank?(params["slug"]) ->
        Map.put(params, "slug", Newton.Slug.slugify(params["title"]))

      true ->
        params
    end
  end

  defp untitled?(title, placeholder_title), do: blank?(title) or title == placeholder_title

  defp blank?(value), do: value |> to_string() |> String.trim() == ""

  @doc """
  The fields that arrived blank and that the server refilled: each `field`
  submitted blank in `incoming` (the raw submission, before
  `keep_persisted_identity/2` repairs it) whose `resolved` value is not, paired
  with that value. That covers a derived field the author cleared and a stale
  blank title or slug put back from the record. The refill usually matches what
  the form last rendered, so LiveView sends no DOM change and the browser needs
  it pushed to stop showing a blank. A field missing from `incoming` was not
  submitted, so it was not cleared.
  """
  @spec derived_refills(map(), map(), [atom()]) :: [{atom(), String.t()}]
  def derived_refills(incoming, resolved, fields) do
    for field <- fields,
        key = Atom.to_string(field),
        cleared?(incoming[key]),
        value = resolved[key],
        not blank?(value),
        do: {field, value}
  end

  defp cleared?(value), do: is_binary(value) and blank?(value)

  @doc """
  Push a `"fill_derived"` event for each of `derived_refills/3`, addressed by the
  field's DOM id in `form`.
  """
  @spec push_derived_refills(
          Phoenix.LiveView.Socket.t(),
          Phoenix.HTML.Form.t(),
          map(),
          map(),
          [atom()]
        ) :: Phoenix.LiveView.Socket.t()
  def push_derived_refills(socket, form, incoming, resolved, fields) do
    incoming
    |> derived_refills(resolved, fields)
    |> Enum.reduce(socket, fn {field, value}, socket ->
      Phoenix.LiveView.push_event(socket, "fill_derived", %{id: form[field].id, value: value})
    end)
  end

  @doc """
  Put the persisted record's title and slug back where a submission carries them
  blank and untouched. An untouched field can't have been cleared by the author,
  so its blank is a stale browser value, such as one sent just after a create
  gave the draft its identity.
  """
  @spec keep_persisted_identity(map(), map()) :: map()
  def keep_persisted_identity(params, record) do
    Enum.reduce(~w(title slug)a, params, fn field, params ->
      key = Atom.to_string(field)
      persisted = Map.get(record, field)

      if unused?(params, key) and blank?(params[key]) and not blank?(persisted) do
        Map.put(params, key, persisted)
      else
        params
      end
    end)
  end

  @doc """
  Does `record` still carry the identity a create backfills for a draft that had
  no title: the placeholder title plus a `slug_prefix` or `slug_prefix-N` slug?
  Such a slug was never chosen by the author, so it keeps following the title.
  """
  @spec placeholder_identity?(map(), String.t(), String.t()) :: boolean()
  def placeholder_identity?(%{title: title, slug: slug}, placeholder_title, slug_prefix)
      when is_binary(slug) do
    title == placeholder_title and Newton.Slug.in_sequence?(slug, slug_prefix)
  end

  def placeholder_identity?(_record, _placeholder_title, _slug_prefix), do: false

  @doc """
  The form for a create the database refused. LiveView's `_unused_` markers are
  dropped so the errors render even on fields the author never touched.
  """
  @spec failed_create_form(Ecto.Changeset.t()) :: Phoenix.HTML.Form.t()
  def failed_create_form(%Ecto.Changeset{} = changeset) do
    params = Map.reject(changeset.params || %{}, fn {key, _} -> unused_marker?(key) end)

    %{changeset | params: params, action: :insert}
    |> Phoenix.Component.to_form()
  end

  defp unused_marker?(key), do: String.starts_with?(key, "_unused_")
end
