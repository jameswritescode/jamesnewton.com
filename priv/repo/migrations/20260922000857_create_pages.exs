defmodule Newton.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :body_markdown, :text, null: false
      add :body_html, :text, null: false
      add :meta_description, :string
      add :published, :boolean, null: false, default: false
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:slug])
    create index(:pages, [:published])
  end
end
