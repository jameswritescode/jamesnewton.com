defmodule Newton.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :excerpt, :string
      add :body_markdown, :text, null: false
      add :body_html, :text, null: false
      add :reading_time, :integer
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:slug])
    create index(:posts, [:published_at])
  end
end
