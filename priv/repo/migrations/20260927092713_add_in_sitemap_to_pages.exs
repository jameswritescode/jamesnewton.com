defmodule Newton.Repo.Migrations.AddInSitemapToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :in_sitemap, :boolean, null: false, default: false
    end
  end
end
