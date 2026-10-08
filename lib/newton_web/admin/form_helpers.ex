defmodule NewtonWeb.Admin.FormHelpers do
  @moduledoc "Shared helpers for admin LiveView forms."

  @doc """
  Derive a param field from another until the user takes it over. Returns
  `{params, new_auto}`: when locked, params and the previous auto value pass
  through unchanged; when unlocked, `derive` recomputes the value, writes it into
  params, and becomes the new auto baseline.
  """
  def autofill(params, _field, true, prev_auto, _derive), do: {params, prev_auto}

  def autofill(params, field, false, _prev_auto, derive) do
    value = derive.()
    {Map.put(params, field, value), value}
  end

  @doc "Did LiveView mark `key` as untouched in this submission?"
  def unused?(params, key), do: Map.has_key?(params, "_unused_" <> key)

  @doc """
  A derived field (slug, excerpt, meta description) locks only once the author
  edits it. The author touched it when LiveView drops the field's `_unused_`
  marker; the value a browser submits for an untouched field can lag the derived
  value, so a bare value comparison would lock it spuriously.
  """
  def field_edited?(params, key, auto), do: not unused?(params, key) and params[key] != auto

  @doc """
  Does `record` still carry the identity a create backfills for a draft that had
  no title: the placeholder title plus a `slug_prefix` or `slug_prefix-N` slug?
  Such a slug was never chosen by the author, so it keeps following the title.
  """
  def placeholder_identity?(%{title: title, slug: slug}, placeholder_title, slug_prefix)
      when is_binary(slug) do
    title == placeholder_title and
      (slug == slug_prefix or Regex.match?(~r/\A#{Regex.escape(slug_prefix)}-\d+\z/, slug))
  end

  def placeholder_identity?(_record, _placeholder_title, _slug_prefix), do: false

  @doc """
  The form for a create the database refused. LiveView's `_unused_` markers are
  dropped so the errors render even on fields the author never touched.
  """
  def failed_create_form(%Ecto.Changeset{} = changeset) do
    params = Map.reject(changeset.params || %{}, fn {key, _} -> unused_marker?(key) end)

    %{changeset | params: params, action: :insert}
    |> Phoenix.Component.to_form()
  end

  defp unused_marker?(key), do: String.starts_with?(key, "_unused_")
end
