defmodule Newton.Markdown do
  @moduledoc """
  Server-side Markdown rendering via MDEx (Lumis highlighter), plus excerpt
  and reading-time derivation. Output uses CSS classes (the `:html_linked`
  formatter) so the warm light/dark syntax palette is driven by `--syntax-*`
  tokens in `assets/css/site.css`.
  """

  @words_per_minute 200
  @excerpt_max_chars 200

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
    |> MDEx.parse_document!()
    |> first_paragraph_text()
    |> truncate(@excerpt_max_chars)
  end

  @doc "Estimated reading time in whole minutes (minimum 1)."
  def reading_time(markdown) when is_binary(markdown) do
    words =
      markdown
      |> String.split(~r/\s+/, trim: true)
      |> length()

    max(1, ceil(words / @words_per_minute))
  end

  defp first_paragraph_text(%MDEx.Document{nodes: nodes}) do
    case Enum.find(nodes, &match?(%MDEx.Paragraph{}, &1)) do
      nil -> ""
      paragraph -> paragraph |> node_text() |> normalize_ws()
    end
  end

  defp node_text(%MDEx.Text{literal: literal}), do: literal
  defp node_text(%MDEx.Code{literal: literal}), do: literal
  defp node_text(%MDEx.SoftBreak{}), do: " "
  defp node_text(%MDEx.LineBreak{}), do: " "
  defp node_text(%{nodes: nodes}) when is_list(nodes), do: Enum.map_join(nodes, "", &node_text/1)
  defp node_text(_), do: ""

  defp normalize_ws(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()

  defp truncate(text, max) do
    if String.length(text) <= max do
      text
    else
      text
      |> String.slice(0, max)
      |> String.replace(~r/\s+\S*$/, "")
      |> Kernel.<>("…")
    end
  end
end
