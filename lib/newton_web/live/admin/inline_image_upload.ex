defmodule NewtonWeb.Admin.InlineImageUpload do
  @moduledoc """
  The inline-image upload flow shared by the post and page editors: store the
  file, record it on the owner's image ledger, and push `insert_image` back to
  the CodeMirror hook. The owner (post vs page) is supplied via `opts`.
  """
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3, put_flash: 3]
  require Logger

  @accept ~w(.jpg .jpeg .png .webp .gif)
  @max_entries 10
  @max_file_size 50_000_000

  def accept, do: @accept
  def max_entries, do: @max_entries
  def max_file_size, do: @max_file_size

  @doc "Describe the files the client-side hook refused, for a flash message."
  def rejected_summary(rejected) do
    Enum.map_join(rejected, ", ", fn item ->
      "#{item["name"]} (#{rejection_reason(item["reason"])})"
    end)
  end

  defp rejection_reason("type"), do: "unsupported type"
  defp rejection_reason("size"), do: "larger than #{div(@max_file_size, 1_000_000)}MB"
  defp rejection_reason(_), do: "too many files at once"

  @doc "Split a `token--filename` client name into `{token, filename}` (token may be nil)."
  def split_token(client_name) do
    case Regex.run(~r/^([0-9a-f]{6})--(.+)$/, client_name) do
      [_, token, filename] -> {token, filename}
      _ -> {nil, client_name}
    end
  end

  def handle_progress(entry, socket, opts) do
    if entry.done? do
      {socket, record} = opts.ensure.(socket)
      {token, filename} = split_token(entry.client_name)

      url =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          case Newton.Storage.store(path, filename) do
            {:ok, key} ->
              opts.attach.(record, key, filename)
              {:ok, Newton.Storage.url(key)}

            {:error, reason} ->
              Logger.warning("inline image store failed for #{filename}: #{inspect(reason)}")
              {:ok, nil}
          end
        end)

      if url do
        {:noreply,
         push_event(socket, "insert_image", %{url: url, alt: "", name: filename, token: token})}
      else
        {:noreply, put_flash(socket, :error, "Couldn't add #{filename} — not a supported image.")}
      end
    else
      {:noreply, socket}
    end
  end
end
