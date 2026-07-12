defmodule Newton.Repo.Migrations.CreatePostImages do
  use Ecto.Migration

  def change do
    create table(:post_images) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :original_filename, :string

      timestamps(type: :utc_datetime)
    end

    create index(:post_images, [:post_id])
    create unique_index(:post_images, [:key])
  end
end
