defmodule Newton.Release do
  @moduledoc """
  Release tasks run in production where Mix is unavailable: database
  migrations and one-off admin creation.

  Create the admin from a running release:

      bin/newton eval 'Newton.Release.create_admin("you@example.com", "a-strong-password")'
  """

  alias Newton.Accounts.User
  alias Newton.Repo

  @app :newton

  @doc "Run all pending migrations for every repo in the app."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Roll a single repo back to `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Create the single confirmed admin account with email + password.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def create_admin(email, password) do
    %User{}
    |> User.email_changeset(%{email: email})
    |> User.password_changeset(%{password: password})
    |> User.confirm_changeset()
    |> Repo.insert()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
