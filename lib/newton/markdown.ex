defmodule Newton.Markdown do
  @moduledoc """
  Server-side Markdown rendering via MDEx (Lumis highlighter), plus excerpt
  and reading-time derivation. Output uses CSS classes (the `:html_linked`
  formatter) so the warm light/dark syntax palette is driven by `--syntax-*`
  tokens in `assets/css/site.css`.
  """

  @words_per_minute 200
  @excerpt_max 200

  @extension [
    table: true,
    strikethrough: true,
    autolink: true,
    tasklist: true,
    footnotes: true
  ]

  @doc "Render Markdown to highlighted, escape-safe HTML."
  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: @extension,
      render: [unsafe: false],
      syntax_highlight: [engine: :lumis, opts: [formatter: :html_linked]]
    )
  end

  @doc "Plain-text excerpt from the first paragraph, truncated at a word boundary."
  def excerpt(markdown) when is_binary(markdown) do
    markdown
    |> first_paragraph()
    |> strip_markdown()
    |> truncate(@excerpt_max)
  end

  @doc "Estimated reading time in whole minutes (minimum 1)."
  def reading_time(markdown) when is_binary(markdown) do
    words =
      markdown
      |> String.split(~r/\s+/, trim: true)
      |> length()

    max(1, ceil(words / @words_per_minute))
  end

  defp first_paragraph(markdown) do
    markdown
    |> String.split(~r/\n\s*\n/, parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp strip_markdown(text) do
    text
    |> String.replace(~r/!?\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[*_`#>]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text

  defp truncate(text, max) do
    text
    |> binary_part(0, max)
    |> String.replace(~r/\s+\S*$/, "")
    |> Kernel.<>("…")
  end
end
