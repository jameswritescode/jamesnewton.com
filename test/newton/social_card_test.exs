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
        published_on: ~D[2026-04-17],
        reading_time: 12
      })

    assert dims(png) == {1200, 630}
  end

  test "post_card renders without a publish date" do
    {:ok, png} =
      SocialCard.post_card(%{
        title: "Navigating the New Software Development Paradigm",
        published_on: nil,
        reading_time: 1
      })

    assert dims(png) == {1200, 630}
  end
end
