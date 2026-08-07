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
    field :lock_version, :integer, default: 1

    has_many :images, Newton.Blog.PostImage

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
    |> clear_preview_token_when_live()
    |> ensure_body()
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
    |> optimistic_lock(:lock_version)
    |> render_derived_fields()
  end

  # A token is only redundant once the post is readable without it. Scheduling
  # sets published_at to a future date, and the post stays private until then —
  # clearing on any published_at would silently break a link already shared.
  defp clear_preview_token_when_live(changeset) do
    if changeset |> get_field(:published_at) |> live?() do
      put_change(changeset, :preview_token, nil)
    else
      changeset
    end
  end

  @doc "Whether `published_at` puts the post in front of readers right now."
  @spec live?(DateTime.t() | nil) :: boolean()
  def live?(nil), do: false
  def live?(%DateTime{} = at), do: DateTime.compare(at, DateTime.utc_now()) != :gt

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
  @spec rerender_changeset(%__MODULE__{}) :: Ecto.Changeset.t()
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
