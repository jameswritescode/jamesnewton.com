defmodule Newton.Repo.Migrations.AddThumbKeyToPhotos do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :thumb_key, :string
    end
  end
end
