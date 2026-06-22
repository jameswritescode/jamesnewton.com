defmodule Newton.SocialCard do
  @moduledoc "Renders 1200x630 Open Graph card PNGs (libvips via the image lib)."

  @width 1200
  @height 630
  @pad 80
  @content_width @width - 2 * @pad

  @palettes %{
    red: %{bg: "#aa4040", fg: "#ffe8d6", muted: "#f3c9b0"},
    dark: %{bg: "#151311", fg: "#eed3ba", muted: "#ad9987"}
  }
  @default_palette :dark

  @title_top 150
  @excerpt_max_chars 160
  @stripe_height 20

  @spec post_card(
          %{
            title: String.t(),
            excerpt: String.t() | nil,
            published_on: Date.t() | nil,
            reading_time: integer()
          },
          atom()
        ) :: {:ok, binary()} | {:error, term()}
  def post_card(post, palette \\ @default_palette) do
    p = Map.fetch!(@palettes, palette)

    secondary =
      [Newton.Format.format_date(post.published_on), "#{post.reading_time} min read"]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("  ·  ")

    footer_y = @height - @pad - 24

    with {:ok, base} <- Image.new(@width, @height, color: p.bg),
         {:ok, stripe} <- Image.new(@width, @stripe_height, color: p.fg),
         {:ok, canvas} <- Image.compose(base, stripe, x: 0, y: @height - @stripe_height),
         {:ok, brand} <- text("James Newton", size: 50, color: p.fg),
         {:ok, title} <- text(post.title, size: title_size(post.title), color: p.fg, wrap: true),
         {:ok, sub} <- text(secondary, size: 24, color: p.muted),
         {:ok, c1} <- Image.compose(canvas, brand, x: @pad, y: @pad),
         {:ok, c2} <- Image.compose(c1, title, x: @pad, y: @title_top),
         excerpt_y = @title_top + Image.height(title) + 32,
         {:ok, c3} <- with_excerpt(c2, card_excerpt(post.excerpt), p.muted, excerpt_y),
         {:ok, c4} <- Image.compose(c3, sub, x: @pad, y: footer_y) do
      Image.write(c4, :memory, suffix: ".png")
    end
  end

  defp text(string, opts) do
    base = [font: "Lora", font_size: opts[:size], text_fill_color: opts[:color], align: :left]
    base = if opts[:wrap], do: Keyword.put(base, :width, @content_width), else: base
    Image.Text.text(string, base)
  end

  # Scale the title down as it gets longer so short titles stay large and long
  # ones shrink and wrap to a second line rather than running off the card.
  defp title_size(title) when byte_size(title) > 70, do: 52
  defp title_size(title) when byte_size(title) > 40, do: 64
  defp title_size(_), do: 75

  defp with_excerpt(canvas, "", _color, _y), do: {:ok, canvas}

  defp with_excerpt(canvas, excerpt, color, y) do
    with {:ok, layer} <- text(excerpt, size: 30, color: color, wrap: true) do
      Image.compose(canvas, layer, x: @pad, y: y)
    end
  end

  defp card_excerpt(nil), do: ""

  defp card_excerpt(excerpt) when is_binary(excerpt) do
    if String.length(excerpt) > @excerpt_max_chars do
      (String.slice(excerpt, 0, @excerpt_max_chars - 1) |> String.trim_trailing()) <> "…"
    else
      excerpt
    end
  end
end
