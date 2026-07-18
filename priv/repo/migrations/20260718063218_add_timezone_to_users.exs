defmodule Newton.Repo.Migrations.AddTimezoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :timezone, :string, null: false, default: "America/Los_Angeles"
    end
  end
end
