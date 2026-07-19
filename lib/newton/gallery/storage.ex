defmodule Newton.Gallery.Storage do
  @moduledoc "Owns image files on disk under the configured media_root."

  @spec store(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, File.posix() | :badarg | :unsupported_content}
  def store(source_path, original_filename) do
    ext = original_filename |> Path.extname() |> String.downcase()
    key = Ecto.UUID.generate() <> ext
    dest = Path.join(media_root(), key)

    with :ok <- verify_image(source_path),
         :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.cp(source_path, dest) do
      {:ok, key}
    end
  end

  # The client-supplied extension is already allowlisted upstream, but the bytes
  # are not — confirm the file's magic number matches a supported image so a
  # renamed script/HTML file can never land under media_root.
  defp verify_image(source_path) do
    case File.open(source_path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, header} when is_binary(header) ->
        if image?(header), do: :ok, else: {:error, :unsupported_content}

      {:ok, _} ->
        {:error, :unsupported_content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp image?(<<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp image?(<<0x89, "PNG\r\n", 0x1A, 0x0A, _::binary>>), do: true
  defp image?(<<"GIF8", _::binary>>), do: true
  defp image?(<<"RIFF", _::32, "WEBP", _::binary>>), do: true
  defp image?(_), do: false

  @spec delete(String.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(key) when is_binary(key) do
    media_root() |> Path.join(key) |> File.rm()
    :ok
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)
end
