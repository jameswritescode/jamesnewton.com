defmodule Newton.Repo.Migrations.AddLockVersionToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
