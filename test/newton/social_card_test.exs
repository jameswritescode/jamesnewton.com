defmodule Newton.SocialCardTest do
  use ExUnit.Case, async: true
  alias Newton.SocialCard

  defp dims(binary) do
    {:ok, img} = Image.from_binary(binary)
    {Image.width(img), Image.height(img)}
  end

  test "post_card renders a 1200x630 PNG" do
    {:ok, png} =
      SocialCard.post_card(%{
        title: "A Short Title",
        excerpt: "A brief, readable summary of the post that sits under the title.",
        published_on: ~D[2026-04-17],
        reading_time: 5
      })

    assert <<0x89, "PNG", _::binary>> = png
    assert dims(png) == {1200, 630}
  end

  test "post_card scales and wraps a long title without overflowing" do
    {:ok, png} =
      SocialCard.post_card(%{
        title: "Building Resilient Background Jobs with Oban and Postgres Advisory Locks",
        excerpt: "Lessons from running tens of millions of jobs a day.",
        published_on: ~D[2026-04-17],
        reading_time: 12
      })

    assert dims(png) == {1200, 630}
  end

  test "post_card survives an excerpt whose wrap renders wider than the text box" do
    excerpt =
      "After 4 years, I left Shopify in December of last year to jump back into " <>
        "the startup game, joining Mark OS. It was a great journey for me, and I " <>
        "worked with a lot of great people, doing some of the…"

    {:ok, png} =
      SocialCard.post_card(%{
        title: "Navigating the New Software Development Paradigm",
        excerpt: excerpt,
        published_on: nil,
        reading_time: 1
      })

    assert dims(png) == {1200, 630}
  end

  test "post_card renders with a nil excerpt" do
    {:ok, png} =
      SocialCard.post_card(%{
        title: "No Excerpt Here",
        excerpt: nil,
        published_on: ~D[2026-04-17],
        reading_time: 3
      })

    assert dims(png) == {1200, 630}
  end
end
