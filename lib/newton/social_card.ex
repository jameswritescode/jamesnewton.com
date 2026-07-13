defmodule Newton.SocialCard do
  @moduledoc "Renders 1200x630 Open Graph card PNGs (libvips via the image lib)."
  alias Newton.Format

  @width 1200
  @height 630
  @pad 80
  @content_width @width - 2 * @pad

  # The site's single dark theme — bg / text / muted, matching site.css.
  @theme %{bg: "#151311", fg: "#eed3ba", muted: "#ad9987"}

  # Vertical rhythm matched to the Figma design (ink-to-ink), measured from each
  # block's rendered bottom. The brand→title gap is intentionally larger than
  # title→excerpt — it reads as even because of the fonts' line-box leading.
  @brand_top 65
  @brand_title_gap 56
  @title_excerpt_gap 32
  @excerpt_max_chars 160
  @stripe_height 20

  @spec post_card(%{
          title: String.t(),
          excerpt: String.t() | nil,
          published_on: Date.t() | nil,
          reading_time: integer()
        }) :: {:ok, binary()} | {:error, term()}
  def post_card(post) do
    p = @theme

    secondary =
      [Format.format_date(post.published_on), Format.format_reading_time(post.reading_time)]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("  ·  ")

    footer_y = @height - @pad - 24

    with {:ok, base} <- Image.new(@width, @height, color: rgb(p.bg)),
         {:ok, stripe} <- Image.new(@width, @stripe_height, color: rgb(p.fg)),
         {:ok, canvas} <- Image.compose(base, stripe, x: 0, y: @height - @stripe_height),
         {:ok, brand} <- text("James Newton", size: 50, color: p.fg),
         {:ok, title} <- text(post.title, size: title_size(post.title), color: p.fg, wrap: true),
         {:ok, sub} <- text(secondary, size: 24, color: p.muted),
         {:ok, c1} <- Image.compose(canvas, brand, x: @pad, y: @brand_top),
         title_y = @brand_top + Image.height(brand) + @brand_title_gap,
         {:ok, c2} <- Image.compose(c1, title, x: @pad, y: title_y),
         excerpt_y = title_y + Image.height(title) + @title_excerpt_gap,
         {:ok, c3} <- with_excerpt(c2, card_excerpt(post.excerpt), p.muted, excerpt_y),
         {:ok, c4} <- Image.compose(c3, sub, x: @pad, y: footer_y) do
      Image.write(c4, :memory, suffix: ".png")
    end
  end

  # Image.new's :color option is typed as a number/pixel list (hex strings work at
  # runtime via Pixel.to_srgb but aren't in the spec), so feed it RGB.
  defp rgb("#" <> hex) do
    [r, g, b] =
      for pair <- [binary_part(hex, 0, 2), binary_part(hex, 2, 2), binary_part(hex, 4, 2)] do
        String.to_integer(pair, 16)
      end

    [r, g, b]
  end

  defp text(string, opts) do
    base = [font: "Lora", font_size: opts[:size], text_fill_color: opts[:color], align: :left]

    if opts[:wrap] do
      wrapped_text(string, base, @content_width)
    else
      Image.Text.text(string, base)
    end
  end

  # libvips treats :width as a soft wrap target and can render a line a few
  # pixels wider, which its own bounds check then refuses to place; narrowing
  # the box makes pango break the line earlier.
  defp wrapped_text(string, base, width) when width > @content_width - 100 do
    case Image.Text.text(string, Keyword.put(base, :width, width)) do
      {:error, %Image.Error{message: "Location" <> _}} -> wrapped_text(string, base, width - 20)
      other -> other
    end
  end

  defp wrapped_text(string, base, width) do
    Image.Text.text(string, Keyword.put(base, :width, width))
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
