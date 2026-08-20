defmodule Newton.ErrorFilter do
  @moduledoc """
  Scrubs sensitive values from ErrorTracker's captured request context before
  it is persisted. ErrorTracker already redacts the authorization/cookie
  headers; this redacts credential-bearing request params (e.g. a password
  submitted to the login controller when a request raises mid-handler) and the
  draft preview token, which grants read access to an unpublished post for as
  long as the link stays enabled.
  """
  @behaviour ErrorTracker.Filter

  @redacted "[REDACTED]"
  # Exact keys: short, high-value names ("p" preview token, "code") that a
  # substring rule can't target without over-matching (`p` is in every word).
  @sensitive ~w(password current_password new_password code app_password token secret p)
  # Substrings: credential families where any key containing them is a secret —
  # client_secret, refresh_token, access_token, code_verifier, the *_password set.
  @sensitive_substrings ~w(secret token password verifier)
  @param_keys ~w(request.params live_view.params)

  @impl true
  def sanitize(context) do
    context
    |> scrub_params()
    |> scrub_query()
  end

  defp scrub_params(context) do
    Enum.reduce(@param_keys, context, fn key, acc ->
      case acc do
        %{^key => params} when is_map(params) -> Map.put(acc, key, scrub(params))
        _ -> acc
      end
    end)
  end

  # ErrorTracker stores the raw query string alongside the parsed params, so the
  # token has to be removed from both.
  defp scrub_query(%{"request.query" => query} = context) when is_binary(query) do
    Map.put(context, "request.query", scrub_query_string(query))
  end

  defp scrub_query(context), do: context

  defp scrub_query_string(query) do
    query
    |> String.split("&")
    |> Enum.map_join("&", fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, _value] ->
          if sensitive_key?(key), do: "#{key}=#{@redacted}", else: pair

        _ ->
          pair
      end
    end)
  end

  defp scrub(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if is_binary(key) and sensitive_key?(key) do
        {key, @redacted}
      else
        {key, scrub(value)}
      end
    end)
  end

  defp scrub(list) when is_list(list), do: Enum.map(list, &scrub/1)
  defp scrub(value), do: value

  defp sensitive_key?(key) do
    key = String.downcase(key)
    key in @sensitive or Enum.any?(@sensitive_substrings, &String.contains?(key, &1))
  end
end
