defmodule Newton.ErrorFilter do
  @moduledoc """
  Scrubs sensitive values from ErrorTracker's captured request context before
  it is persisted. ErrorTracker already redacts the authorization/cookie
  headers; this redacts credential-bearing request params (e.g. a password
  submitted to the login controller when a request raises mid-handler).
  """
  @behaviour ErrorTracker.Filter

  @sensitive ~w(password current_password new_password code app_password token secret)

  @impl true
  def sanitize(context) do
    case context do
      %{"request.params" => params} when is_map(params) ->
        Map.put(context, "request.params", scrub(params))

      _ ->
        context
    end
  end

  defp scrub(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if is_binary(key) and String.downcase(key) in @sensitive do
        {key, "[REDACTED]"}
      else
        {key, scrub(value)}
      end
    end)
  end

  defp scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)
  defp scrub(value), do: value
end
