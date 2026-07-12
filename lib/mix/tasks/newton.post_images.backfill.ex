defmodule Mix.Tasks.Newton.PostImages.Backfill do
  @shortdoc "Adopt untracked inline post images; audit volume/ledger drift"
  @moduledoc """
  Scans every post body for /media/<key> references, inserts missing
  post_images rows for files present on the volume, and reports (never
  deletes) referenced-but-missing keys and unowned volume files.

      mix newton.post_images.backfill
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    %{adopted: adopted} = Newton.Blog.ImageBackfill.run()
    %{missing: missing, strays: strays} = Newton.Blog.ImageAudit.run()

    Mix.shell().info("adopted: #{length(adopted)}")
    Enum.each(adopted, &Mix.shell().info("  + #{&1}"))

    Mix.shell().info("missing from volume: #{length(missing)}")
    Enum.each(missing, fn {slug, key} -> Mix.shell().info("  ! #{slug}: #{key}") end)

    Mix.shell().info("unowned volume files: #{length(strays)}")
    Enum.each(strays, &Mix.shell().info("  ? #{&1}"))
  end
end
