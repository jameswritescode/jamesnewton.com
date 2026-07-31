defmodule Newton.Gallery.Storage do
  @moduledoc "Owns image files on disk under the configured media_root."

  @spec store(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, File.posix() | :badarg | :unsupported_content}
  def store(source_path, _original_filename) do
    with {:ok, ext} <- image_extension(source_path) do
      key = Ecto.UUID.generate() <> ext
      dest = Path.join(media_root(), key)

      with :ok <- File.mkdir_p(Path.dirname(dest)),
           :ok <- File.cp(source_path, dest) do
        {:ok, key}
      end
    end
  end

  # The stored extension comes from the file's magic number, never from the
  # client. LiveView's `accept` passes an entry whose *declared* MIME type
  # matches even when the filename says otherwise, so a client-supplied ".html"
  # would otherwise be served back from /media as text/html on our own origin.
  defp image_extension(source_path) do
    case File.open(source_path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, header} when is_binary(header) ->
        case extension_for(header) do
          nil -> {:error, :unsupported_content}
          ext -> {:ok, ext}
        end

      {:ok, _} ->
        {:error, :unsupported_content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extension_for(<<0xFF, 0xD8, 0xFF, _::binary>>), do: ".jpg"
  defp extension_for(<<0x89, "PNG\r\n", 0x1A, 0x0A, _::binary>>), do: ".png"
  defp extension_for(<<"GIF8", _::binary>>), do: ".gif"
  defp extension_for(<<"RIFF", _::32, "WEBP", _::binary>>), do: ".webp"
  defp extension_for(_), do: nil

  @spec delete(String.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(key) when is_binary(key) do
    media_root() |> Path.join(key) |> File.rm()
    :ok
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)
end
