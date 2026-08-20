defmodule Newton.Repo.Migrations.WidenOauthRedirectUrisToText do
  use Ecto.Migration

  def change do
    alter table(:oauth_clients) do
      modify :redirect_uris, {:array, :text}, from: {:array, :string}
    end
  end
end
