defmodule Mix.Tasks.Standard.PutPublication do
  @shortdoc "Creates or updates the site.standard.publication record"

  @moduledoc """
  Writes the publication record to the author's PDS repo. Requires
  BSKY_APP_PASSWORD in the environment. Runs regardless of the enabled flag —
  an explicit operator action. Idempotent: rkey "self" upserts.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:req)

    password =
      System.get_env("BSKY_APP_PASSWORD") ||
        Mix.raise("BSKY_APP_PASSWORD is not set")

    config = Application.get_env(:newton, Newton.Standard, [])
    Application.put_env(:newton, Newton.Standard, Keyword.put(config, :app_password, password))

    case Newton.Standard.put_publication() do
      {:ok, uri} -> Mix.shell().info("publication record: #{uri}")
      {:error, reason} -> Mix.raise("put_publication failed: #{inspect(reason)}")
    end
  end
end
