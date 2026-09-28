defmodule Newton.Pages do
  @moduledoc "Standalone markdown pages served at top-level slugs."
  import Ecto.Query
  alias Newton.Repo
  alias Newton.Pages.{Page, PageImage}
  alias Newton.Storage

  @spec list_pages() :: [%Page{}]
  def list_pages do
    Repo.all(from p in Page, order_by: [desc: p.inserted_at, desc: p.id])
  end

  @spec list_published_pages() :: [%Page{}]
  def list_published_pages do
    Repo.all(from p in Page, where: p.published, order_by: [asc: p.slug])
  end

  @spec list_sitemap_pages() :: [%Page{}]
  def list_sitemap_pages do
    Repo.all(from p in Page, where: p.published and p.in_sitemap, order_by: [asc: p.slug])
  end

  @spec get_page!(integer() | String.t()) :: %Page{}
  def get_page!(id), do: Repo.get!(Page, id)

  @spec get_page_by_slug(String.t()) :: %Page{} | nil
  def get_page_by_slug(slug), do: Repo.get_by(Page, slug: slug)

  @spec get_published_page_by_slug(String.t()) :: %Page{} | nil
  def get_published_page_by_slug(slug), do: Repo.get_by(Page, slug: slug, published: true)

  @spec create_page(map()) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}}
  def create_page(attrs) do
    %Page{} |> Page.changeset(attrs) |> Repo.insert()
  end

  @spec update_page(%Page{}, map()) ::
          {:ok, %Page{}} | {:error, %Ecto.Changeset{}} | {:error, :stale}
  def update_page(%Page{} = page, attrs) do
    page |> Page.changeset(attrs) |> Repo.update()
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @spec delete_page(%Page{}) :: {:ok, %Page{}} | {:error, %Ecto.Changeset{}}
  def delete_page(%Page{} = page) do
    page |> list_images() |> Enum.each(&Storage.delete(&1.key))
    Repo.delete(page)
  end

  @spec change_page(%Page{}, map()) :: %Ecto.Changeset{}
  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  @spec count_pages() :: non_neg_integer()
  def count_pages, do: Repo.aggregate(Page, :count, :id)

  @spec count_drafts() :: non_neg_integer()
  def count_drafts, do: Repo.aggregate(from(p in Page, where: p.published == false), :count, :id)

  @spec list_images(%Page{}) :: [%PageImage{}]
  def list_images(%Page{id: page_id}) do
    Repo.all(
      from i in PageImage, where: i.page_id == ^page_id, order_by: [asc: i.inserted_at, asc: i.id]
    )
  end

  @spec attach_image(%Page{}, String.t(), String.t() | nil) ::
          {:ok, %PageImage{}} | {:error, %Ecto.Changeset{}}
  def attach_image(%Page{} = page, key, original_filename \\ nil) do
    %PageImage{page_id: page.id}
    |> PageImage.create_changeset(%{key: key, original_filename: original_filename})
    |> Repo.insert()
  end

  @spec delete_image(%PageImage{}) :: {:ok, %PageImage{}} | {:error, :referenced}
  def delete_image(%PageImage{} = image) do
    page = get_page!(image.page_id)

    if Newton.Images.referenced?(page.body_markdown, image.key) do
      {:error, :referenced}
    else
      Storage.delete(image.key)
      Repo.delete(image)
    end
  end
end
