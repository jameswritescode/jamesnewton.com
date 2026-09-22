defmodule NewtonWeb.Admin.Autosave do
  @moduledoc """
  The debounce + param-staging core shared by the post and page editors. Each
  editor keeps its own persist function and its own gate (posts on published_at,
  pages on the published boolean); this module owns only the generic mechanics.
  """
  @debounce_ms 1500

  def debounce_ms, do: @debounce_ms

  @doc "Autosave field names plus their `_unused_` twins (LiveView drops unchanged params)."
  def keys(fields) when is_list(fields) do
    fields ++ Enum.map(fields, &("_unused_" <> &1))
  end

  @doc "The subset of `params` that participates in autosave."
  def content_params(params, keys), do: Map.take(params, keys)

  @doc "Cancel any pending timer and arm a fresh one; returns the new ref."
  def schedule(timer) do
    if is_reference(timer), do: Process.cancel_timer(timer)
    Process.send_after(self(), :autosave, @debounce_ms)
  end

  @doc "Do the submitted `params` diverge from `record` on any of `fields`?"
  def dirty?(params, record, fields) do
    Enum.any?(fields, fn field ->
      comparable(params[field]) != comparable(Map.get(record, String.to_existing_atom(field)))
    end)
  end

  defp comparable(nil), do: ""
  defp comparable(value), do: value
end
