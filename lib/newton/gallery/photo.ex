defmodule Newton.Gallery.Photo do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Gallery.PhotoGroup

  schema "photos" do
    field :image_key, :string
    field :alt, :string
    field :position, :integer, default: 0
    field :width, :integer
    field :height, :integer

    belongs_to :photo_group, PhotoGroup
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_key, :alt, :position, :width, :height, :photo_group_id])
    |> validate_required([:image_key, :alt, :position])
  end
end
