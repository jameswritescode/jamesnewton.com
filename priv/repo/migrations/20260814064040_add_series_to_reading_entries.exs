defmodule Newton.Repo.Migrations.AddSeriesToReadingEntries do
  use Ecto.Migration

  def change do
    alter table(:reading_entries) do
      add :series, :string
    end
  end
end
