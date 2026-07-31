defmodule NewtonWeb.SEO.HtmlSafeJson do
  @moduledoc """
  Jason wrapper handed to phoenix_seo as its `:json_library`.

  phoenix_seo renders JSON-LD with `Phoenix.HTML.raw/1` inside a `<script>`
  element. Jason's default escaping leaves `<` and `/` untouched, so a value
  containing the literal bytes `</script>` closes the element early and whatever
  follows is parsed as live markup. `escape: :html_safe` escapes those bytes,
  which keeps the payload valid JSON-LD while making the breakout impossible.
  """

  @spec encode!(term()) :: iodata()
  def encode!(data), do: Jason.encode!(data, escape: :html_safe)

  @spec encode!(term(), keyword()) :: iodata()
  def encode!(data, opts), do: Jason.encode!(data, Keyword.put(opts, :escape, :html_safe))

  @spec decode!(iodata()) :: term()
  def decode!(data), do: Jason.decode!(data)
end
