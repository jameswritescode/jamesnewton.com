defmodule Newton.Gallery.Photo do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Gallery.PhotoGroup

  schema "photos" do
    field :image_key, :string
    field :thumb_key, :string
    field :alt, :string, default: ""
    field :position, :integer, default: 0
    field :width, :integer
    field :height, :integer

    belongs_to :photo_group, PhotoGroup
    timestamps(type: :utc_datetime)
  end

  @doc "Edit changeset: only the author-supplied alt text is mass-assignable."
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:alt])
    |> validate_required([:image_key, :position])
  end

  @doc """
  Creation changeset for the upload flow. The image_key, position, dimensions,
  and group are set by the server (not the editing form), so they are only cast
  here, never in `changeset/2`.
  """
  @spec create_changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_key, :thumb_key, :alt, :position, :width, :height, :photo_group_id])
    |> validate_required([:image_key, :position])
  end
end
