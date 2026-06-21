defmodule Newton.Accounts.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :label, :string
    field :last_used_at, :utc_datetime
    belongs_to :user, Newton.Accounts.User
    timestamps(type: :utc_datetime)
  end

  @doc "Only the human label is form-assignable; key material is set by the server."
  def label_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:label])
    |> validate_required([:label])
    |> validate_length(:label, max: 60)
  end
end
