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
end
