defmodule Newton.Gallery.Thumbnail do
  @moduledoc """
  Generates a downscaled WebP thumbnail of a source image (libvips via the
  `image` lib). Used for the photo grid; the full original is served separately.
  """

  @max_edge 1000
  @quality 75
  @default_max_thumbnail_bytes 350 * 1024 * 1024

  @spec generate(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def generate(source_path) do
    dest = Path.join(System.tmp_dir!(), "thumb-#{System.unique_integer([:positive])}.webp")

    with :ok <- verify_decodable(source_path),
         {:ok, thumb} <- Image.thumbnail(source_path, @max_edge, resize: :down),
         {:ok, _} <- Image.write(thumb, dest, quality: @quality) do
      {:ok, dest}
    else
      error ->
        # Clean up a partially-written file if the write failed (no-op otherwise).
        File.rm(dest)
        error
    end
  end

  # Reject sources whose thumbnail would not fit in the VM before decoding any
  # pixels, since the machine has 1GB and an OOM kills the whole node. Measured
  # peaks: a 102MP JPEG costs ~40MB over baseline and a 900MP PNG ~440MB, both
  # roughly half a byte per pixel because libvips streams scanlines. Interlaced
  # PNGs are the outlier — Adam7 has no scanline order, so the full raster is
  # materialized and a 400MP file peaks near 1.5GB. Hence one byte per pixel
  # budgeted for streamable sources and a byte per band for interlaced ones,
  # which leaves any real camera file (100MP today) far inside the limit.
  defp verify_decodable(source_path) do
    case Image.open(source_path, access: :sequential) do
      {:ok, image} ->
        if estimated_peak_bytes(image) <= max_thumbnail_bytes() do
          :ok
        else
          {:error, :image_too_large}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp estimated_peak_bytes(image) do
    pixels = Image.width(image) * Image.height(image)
    if streamable?(image), do: pixels, else: pixels * Image.bands(image)
  end

  defp streamable?(image) do
    case Vix.Vips.Image.header_value(image, "interlaced") do
      {:ok, 1} -> false
      _ -> true
    end
  end

  defp max_thumbnail_bytes do
    Application.get_env(:newton, :max_thumbnail_bytes, @default_max_thumbnail_bytes)
  end
end
