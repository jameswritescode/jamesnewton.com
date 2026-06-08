defmodule Newton.Repo.Migrations.CreateReadingEntries do
  use Ecto.Migration

  def change do
    create table(:reading_entries) do
      add :title, :string, null: false
      add :author, :string, null: false
      add :link, :string
      add :note, :string
      add :status, :string, null: false
      add :finished_at, :date

      timestamps(type: :utc_datetime)
    end

    create index(:reading_entries, [:finished_at])
  end
end
