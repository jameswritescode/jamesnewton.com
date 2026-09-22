defmodule Newton.Repo.Migrations.CreatePageImages do
  use Ecto.Migration

  def change do
    create table(:page_images) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :original_filename, :string
      timestamps(type: :utc_datetime)
    end

    create index(:page_images, [:page_id])
    create unique_index(:page_images, [:key])
  end
end
