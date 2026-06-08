defmodule Newton.Gallery.PhotoGroup do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Gallery.Photo

  schema "photo_groups" do
    field :slug, :string
    field :title, :string
    field :caption, :string
    field :taken_on, :date

    has_many :photos, Photo, preload_order: [asc: :position]
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:slug, :title, :caption, :taken_on])
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
  end
end
