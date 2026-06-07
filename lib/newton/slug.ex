defmodule Newton.Slug do
  @moduledoc "Deterministic slugs from titles."
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
