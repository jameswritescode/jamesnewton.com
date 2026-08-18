defmodule Newton.OAuth.Grant do
  use Ecto.Schema

  alias Newton.OAuth.Client

  schema "oauth_grants" do
    belongs_to :client, Client
    field :code_hash, :binary
    field :code_expires_at, :utc_datetime
    field :code_used_at, :utc_datetime
    field :code_challenge, :string
    field :redirect_uri, :string
    field :resource, :string
    field :access_token_hash, :binary
    field :access_token_expires_at, :utc_datetime
    field :refresh_token_hash, :binary
    field :previous_refresh_token_hash, :binary
    field :refresh_token_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
