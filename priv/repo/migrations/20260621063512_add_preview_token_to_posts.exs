defmodule Newton.Repo.Migrations.AddPreviewTokenToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :preview_token, :string
    end
  end
end
