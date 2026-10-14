defmodule Newton.Slug do
  @moduledoc "Deterministic slugs from titles."
  @spec slugify(String.t()) :: String.t()
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc "Is `slug` one of the series `prefix`, `prefix-2`, `prefix-3`, …?"
  @spec in_sequence?(String.t(), String.t()) :: boolean()
  def in_sequence?(slug, prefix) do
    slug == prefix or Regex.match?(~r/\A#{Regex.escape(prefix)}-\d+\z/, slug)
  end

  @doc "The first slug in the series `prefix`, `prefix-2`, … that `taken` lacks."
  @spec first_free(String.t(), Enumerable.t()) :: String.t()
  def first_free(prefix, taken) do
    taken = taken |> Enum.filter(&in_sequence?(&1, prefix)) |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&numbered(prefix, &1))
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp numbered(prefix, 1), do: prefix
  defp numbered(prefix, n), do: "#{prefix}-#{n}"
end
