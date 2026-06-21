defmodule Newton.Repo.Migrations.CreateUserRecoveryCodes do
  use Ecto.Migration

  def change do
    create table(:user_recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_recovery_codes, [:user_id, :code_hash])
    create index(:user_recovery_codes, [:user_id])
  end
end
