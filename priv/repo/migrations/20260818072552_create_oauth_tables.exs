defmodule Newton.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  def change do
    create table(:oauth_clients) do
      add :client_id, :string, null: false
      add :client_secret_hash, :binary
      add :client_name, :string, null: false
      add :redirect_uris, {:array, :string}, null: false
      add :token_endpoint_auth_method, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_clients, [:client_id])

    create table(:oauth_grants) do
      add :client_id, references(:oauth_clients, on_delete: :delete_all), null: false
      add :code_hash, :binary
      add :code_expires_at, :utc_datetime
      add :code_used_at, :utc_datetime
      add :code_challenge, :string, null: false
      add :redirect_uri, :string, null: false
      add :resource, :string, null: false
      add :access_token_hash, :binary
      add :access_token_expires_at, :utc_datetime
      add :refresh_token_hash, :binary
      add :previous_refresh_token_hash, :binary
      add :refresh_token_expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_grants, [:code_hash])
    create index(:oauth_grants, [:access_token_hash])
    create index(:oauth_grants, [:refresh_token_hash])
    create index(:oauth_grants, [:previous_refresh_token_hash])
    create index(:oauth_grants, [:client_id])
  end
end
