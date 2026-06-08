defmodule Newton.Repo.Migrations.CreatePhotoGroups do
  use Ecto.Migration

  def change do
    create table(:photo_groups) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :caption, :text
      add :taken_on, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:photo_groups, [:slug])
    create index(:photo_groups, [:taken_on])
  end
end
