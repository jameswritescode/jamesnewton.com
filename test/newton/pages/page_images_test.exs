defmodule Newton.Pages.PageImagesTest do
  use Newton.DataCase
  alias Newton.Pages

  defp page_fixture(attrs \\ %{}) do
    {:ok, page} =
      attrs
      |> Enum.into(%{
        slug: "page-#{System.unique_integer([:positive])}",
        title: "A Page",
        body_markdown: "Some text."
      })
      |> Pages.create_page()

    page
  end

  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "attach_image records an upload against its page" do
    page = page_fixture()
    assert {:ok, image} = Pages.attach_image(page, "abc123.png", "shot.png")
    assert image.page_id == page.id
    assert [%{key: "abc123.png"}] = Pages.list_images(page)
  end

  test "delete_image removes the file and row for an unreferenced image" do
    page = page_fixture()
    {:ok, image} = Pages.attach_image(page, "gone.png", nil)
    path = stored_file("gone.png")
    assert {:ok, _} = Pages.delete_image(image)
    refute File.exists?(path)
    assert Pages.list_images(page) == []
  end

  test "delete_image refuses while the page still references the image" do
    page = page_fixture(%{body_markdown: "![](/media/kept.png)"})
    {:ok, image} = Pages.attach_image(page, "kept.png", nil)
    path = stored_file("kept.png")
    assert {:error, :referenced} = Pages.delete_image(image)
    assert File.exists?(path)
  end

  test "deleting a page cascades its image rows" do
    page = page_fixture()
    {:ok, _} = Pages.attach_image(page, "sweep.png", nil)
    path = stored_file("sweep.png")
    {:ok, _} = Pages.delete_page(page)
    assert Pages.list_images(page) == []
    refute File.exists?(path)
  end
end
