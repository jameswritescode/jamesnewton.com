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
end
