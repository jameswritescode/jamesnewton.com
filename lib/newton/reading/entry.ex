defmodule Newton.Reading.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reading_entries" do
    field :title, :string
    field :author, :string
    field :link, :string
    field :note, :string
    field :series, :string
    field :status, Ecto.Enum, values: [:reading, :read, :listening, :listened]
    field :finished_at, :date

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :author, :link, :note, :series, :status, :finished_at])
    |> validate_required([:title, :author, :status])
    |> normalize_series()
  end

  defp normalize_series(changeset) do
    case get_change(changeset, :series) do
      series when is_binary(series) ->
        case String.trim(series) do
          "" -> put_change(changeset, :series, nil)
          trimmed -> put_change(changeset, :series, trimmed)
        end

      _ ->
        changeset
    end
  end
end
