defmodule Newton.Images do
  @moduledoc "Pure helpers over image references inside markdown bodies."

  @spec referenced?(String.t() | nil, String.t()) :: boolean()
  def referenced?(body_markdown, key) when is_binary(key) do
    String.contains?(body_markdown || "", key)
  end
end
