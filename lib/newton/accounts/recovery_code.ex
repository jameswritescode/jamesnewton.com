defmodule Newton.Accounts.RecoveryCode do
  use Ecto.Schema

  schema "user_recovery_codes" do
    field :code_hash, :binary
    field :used_at, :utc_datetime
    belongs_to :user, Newton.Accounts.User
    timestamps(type: :utc_datetime)
  end
end
