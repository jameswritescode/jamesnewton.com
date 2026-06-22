defmodule Newton.Gallery.Storage do
  @moduledoc "Owns image files on disk under the configured media_root."

  @spec store(String.t(), String.t()) :: {:ok, String.t()} | {:error, File.posix() | :badarg}
  def store(source_path, original_filename) do
    ext = original_filename |> Path.extname() |> String.downcase()
    key = Ecto.UUID.generate() <> ext
    dest = Path.join(media_root(), key)

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.cp(source_path, dest) do
      {:ok, key}
    end
  end

  @spec delete(String.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(key) when is_binary(key) do
    media_root() |> Path.join(key) |> File.rm()
    :ok
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)
end
