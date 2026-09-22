defmodule Newton.Pages.Page do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Markdown

  @reserved_slugs ~w(posts blog reading photos links resume admin oauth mcp og
                     login logout dev sitemap.xml robots.txt .well-known)

  schema "pages" do
    field :slug, :string
    field :title, :string
    field :body_markdown, :string
    field :body_html, :string
    field :meta_description, :string
    field :published, :boolean, default: false
    field :lock_version, :integer, default: 1
    has_many :images, Newton.Pages.PageImage
    timestamps(type: :utc_datetime)
  end

  @spec reserved_slugs() :: [String.t()]
  def reserved_slugs, do: @reserved_slugs

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:slug, :title, :body_markdown, :meta_description, :published])
    |> ensure_body()
    |> validate_required([:slug, :title])
    |> validate_exclusion(:slug, @reserved_slugs, message: "is reserved")
    |> unique_constraint(:slug)
    |> optimistic_lock(:lock_version)
    |> render_body_html()
  end

  defp ensure_body(changeset) do
    if is_nil(get_field(changeset, :body_markdown)) do
      put_change(changeset, :body_markdown, "")
    else
      changeset
    end
  end

  defp render_body_html(%Ecto.Changeset{valid?: true} = changeset) do
    case fetch_change(changeset, :body_markdown) do
      {:ok, markdown} -> put_change(changeset, :body_html, Markdown.to_html(markdown))
      :error -> changeset
    end
  end

  defp render_body_html(changeset), do: changeset
end
