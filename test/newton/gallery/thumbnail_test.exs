defmodule Newton.Gallery.ThumbnailTest do
  use ExUnit.Case, async: true

  alias Newton.Gallery.Thumbnail

  defp source(w, h) do
    {:ok, img} = Image.new(w, h, color: [40, 30, 20])
    path = Path.join(System.tmp_dir!(), "src-#{System.unique_integer([:positive])}.png")
    {:ok, _} = Image.write(img, path)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp cleanup(path) do
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "downscales the longest edge to 1000 as WebP, preserving aspect ratio" do
    {:ok, thumb_path} = Thumbnail.generate(source(2000, 1500))
    cleanup(thumb_path)

    assert Path.extname(thumb_path) == ".webp"
    {:ok, thumb} = Image.open(thumb_path)
    assert Image.width(thumb) == 1000
    assert Image.height(thumb) == 750
  end

  test "downscales a portrait image on its long (height) edge" do
    {:ok, thumb_path} = Thumbnail.generate(source(3000, 4000))
    cleanup(thumb_path)

    {:ok, thumb} = Image.open(thumb_path)
    assert Image.width(thumb) == 750
    assert Image.height(thumb) == 1000
  end

  test "does not upscale an image already under the cap" do
    {:ok, thumb_path} = Thumbnail.generate(source(400, 300))
    cleanup(thumb_path)

    {:ok, thumb} = Image.open(thumb_path)
    assert Image.width(thumb) == 400
    assert Image.height(thumb) == 300
  end

  test "returns an error for a non-image source" do
    bad = Path.join(System.tmp_dir!(), "bad-#{System.unique_integer([:positive])}.png")
    File.write!(bad, "not an image")

    assert {:error, _} = Thumbnail.generate(bad)
  end
end
