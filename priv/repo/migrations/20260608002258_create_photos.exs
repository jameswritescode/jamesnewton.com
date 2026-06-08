defmodule Newton.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos) do
      add :photo_group_id, references(:photo_groups, on_delete: :delete_all), null: false
      add :image_key, :string, null: false
      add :alt, :string, null: false
      add :position, :integer, null: false, default: 0
      add :width, :integer
      add :height, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:photos, [:photo_group_id])
  end
end
