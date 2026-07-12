defmodule Newton.Blog.PostImage do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Blog.Post

  schema "post_images" do
    field :key, :string
    field :original_filename, :string

    belongs_to :post, Post
    timestamps(type: :utc_datetime)
  end

  @doc "Creation changeset for the upload flow; every field is server-set, never form-cast."
  @spec create_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def create_changeset(image, attrs) do
    image
    |> cast(attrs, [:key, :original_filename])
    |> validate_required([:post_id, :key])
    |> unique_constraint(:key)
    |> foreign_key_constraint(:post_id)
  end
end
