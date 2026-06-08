defmodule Newton.Reading.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reading_entries" do
    field :title, :string
    field :author, :string
    field :link, :string
    field :note, :string
    field :status, Ecto.Enum, values: [:reading, :read, :listening, :listened]
    field :finished_at, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :author, :link, :note, :status, :finished_at])
    |> validate_required([:title, :author, :status])
  end
end
