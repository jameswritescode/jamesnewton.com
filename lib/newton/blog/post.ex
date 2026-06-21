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
    field :preview_token, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
    |> clear_preview_token_when_published()
    |> ensure_body()
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
    |> render_derived_fields()
  end

  # A published post never carries a preview token — every publish path runs the
  # changeset, so clearing it here covers them all.
  defp clear_preview_token_when_published(changeset) do
    if get_field(changeset, :published_at) do
      put_change(changeset, :preview_token, nil)
    else
      changeset
    end
  end

  # The body column is non-null and `cast` nils out empty strings, so a bodyless
  # draft would violate the constraint. Coerce a missing body to "".
  defp ensure_body(changeset) do
    if is_nil(get_field(changeset, :body_markdown)) do
      put_change(changeset, :body_markdown, "")
    else
      changeset
    end
  end

  @doc "Force re-render of derived fields (body_html, excerpt, reading_time) from existing body_markdown."
  def rerender_changeset(%__MODULE__{} = post) do
    post
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:body_markdown, post.body_markdown)
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
