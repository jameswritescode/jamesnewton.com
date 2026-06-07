defmodule Newton.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset
  alias Newton.Markdown

  schema "posts" do
    field :slug, :string
    field :title, :string
    field :excerpt, :string
    field :body_markdown, :string
    field :body_html, :string
    field :reading_time, :integer
    field :published_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
    |> validate_required([:slug, :title, :body_markdown])
    |> unique_constraint(:slug)
    |> render_derived_fields()
  end

  defp render_derived_fields(%Ecto.Changeset{valid?: true} = changeset) do
    case fetch_change(changeset, :body_markdown) do
      {:ok, markdown} ->
        changeset
        |> put_change(:body_html, Markdown.to_html(markdown))
        |> put_change(:reading_time, Markdown.reading_time(markdown))
        |> maybe_put_excerpt(markdown)

      :error ->
        changeset
    end
  end

  defp render_derived_fields(changeset), do: changeset

  defp maybe_put_excerpt(changeset, markdown) do
    case get_field(changeset, :excerpt) do
      nil -> put_change(changeset, :excerpt, Markdown.excerpt(markdown))
      "" -> put_change(changeset, :excerpt, Markdown.excerpt(markdown))
      _present -> changeset
    end
  end
end
