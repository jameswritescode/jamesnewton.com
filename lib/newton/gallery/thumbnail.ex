defmodule Newton.Gallery.Thumbnail do
  @moduledoc """
  Generates a downscaled WebP thumbnail of a source image (libvips via the
  `image` lib). Used for the photo grid; the full original is served separately.
  """

  @max_edge 1000
  @quality 75

  @spec generate(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def generate(source_path) do
    dest = Path.join(System.tmp_dir!(), "thumb-#{System.unique_integer([:positive])}.webp")

    with {:ok, thumb} <- Image.thumbnail(source_path, @max_edge, resize: :down),
         {:ok, _} <- Image.write(thumb, dest, quality: @quality) do
      {:ok, dest}
    else
      error ->
        # Clean up a partially-written file if the write failed (no-op otherwise).
        File.rm(dest)
        error
    end
  end
end
