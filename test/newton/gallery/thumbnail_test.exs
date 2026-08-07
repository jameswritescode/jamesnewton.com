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

  defp interlaced_source(w, h) do
    {:ok, img} = Image.new(w, h, color: [40, 30, 20])
    path = Path.join(System.tmp_dir!(), "int-#{System.unique_integer([:positive])}.png")
    :ok = Vix.Vips.Operation.pngsave(img, path, interlace: true)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "memory budget" do
    setup do
      previous = Application.get_env(:newton, :max_thumbnail_bytes)
      Application.put_env(:newton, :max_thumbnail_bytes, 5_000_000)
      on_exit(fn -> Application.put_env(:newton, :max_thumbnail_bytes, previous) end)
      :ok
    end

    test "refuses an interlaced source over the budget" do
      # 1500x1500 x 3 bands = 6.75M, over the 5M budget: Adam7 forces a full raster.
      assert {:error, :image_too_large} = Thumbnail.generate(interlaced_source(1500, 1500))
    end

    test "allows an interlaced source within the budget" do
      {:ok, thumb_path} = Thumbnail.generate(interlaced_source(800, 800))
      cleanup(thumb_path)

      assert {:ok, _} = Image.open(thumb_path)
    end

    test "budgets a streamable source per pixel, not per band" do
      # 2000x2000 = 4M pixels. Rejected if it were charged per band (12M), and
      # allowed as it actually is, since libvips streams scanlines.
      {:ok, thumb_path} = Thumbnail.generate(source(2000, 2000))
      cleanup(thumb_path)

      assert {:ok, _} = Image.open(thumb_path)
    end

    test "refuses a streamable source far past the budget" do
      assert {:error, :image_too_large} = Thumbnail.generate(source(3000, 3000))
    end
  end
end
