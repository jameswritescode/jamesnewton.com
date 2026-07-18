defmodule Newton.Repo.Migrations.CreateHourlyViews do
  use Ecto.Migration

  def change do
    create table(:hourly_views) do
      add :hour, :utc_datetime, null: false
      add :path, :string, null: false
      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:hourly_views, [:hour, :path])
  end
end
