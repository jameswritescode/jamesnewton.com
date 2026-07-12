defmodule Newton.Blog.PostImagesTest do
  use Newton.DataCase
  alias Newton.Blog

  defp post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        slug: "post-#{System.unique_integer([:positive])}",
        title: "A Post",
        body_markdown: "Some text."
      })
      |> Blog.create_post()

    post
  end

  test "attach_image records an upload against its post" do
    post = post_fixture()

    assert {:ok, image} = Blog.attach_image(post, "abc123.png", "shot.png")
    assert image.post_id == post.id
    assert image.original_filename == "shot.png"
    assert [%{key: "abc123.png"}] = Blog.list_images(post)
  end

  test "a key can only be attached once" do
    post = post_fixture()
    {:ok, _} = Blog.attach_image(post, "dup.png", "a.png")

    assert {:error, changeset} = Blog.attach_image(post, "dup.png", "b.png")
    assert %{key: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_images returns only the post's images, oldest first" do
    post = post_fixture()
    other = post_fixture()
    {:ok, first} = Blog.attach_image(post, "one.png", nil)
    {:ok, second} = Blog.attach_image(post, "two.png", nil)
    {:ok, _} = Blog.attach_image(other, "three.png", nil)

    assert [^first, ^second] = Blog.list_images(post)
  end

  test "image_referenced? reflects whether the body still uses the key" do
    post = post_fixture(%{body_markdown: "Intro\n\n![](/media/used.png)\n"})
    {:ok, used} = Blog.attach_image(post, "used.png", nil)
    {:ok, unused} = Blog.attach_image(post, "unused.png", nil)

    assert Blog.image_referenced?(post, used)
    refute Blog.image_referenced?(post, unused)
  end

  defp stored_file(key) do
    root = Application.fetch_env!(:newton, :media_root)
    File.mkdir_p!(root)
    path = Path.join(root, key)
    File.write!(path, "img-bytes")
    path
  end

  test "delete_image removes the file and the record for an unreferenced image" do
    post = post_fixture()
    {:ok, image} = Blog.attach_image(post, "gone.png", nil)
    path = stored_file("gone.png")

    assert {:ok, _} = Blog.delete_image(image)
    refute File.exists?(path)
    assert Blog.list_images(post) == []
  end

  test "delete_image refuses while the post still references the image" do
    post = post_fixture(%{body_markdown: "![](/media/kept.png)"})
    {:ok, image} = Blog.attach_image(post, "kept.png", nil)
    path = stored_file("kept.png")

    assert {:error, :referenced} = Blog.delete_image(image)
    assert File.exists?(path)
    assert [_] = Blog.list_images(post)
  end

  test "delete_post removes the post's image files" do
    post = post_fixture()
    {:ok, _} = Blog.attach_image(post, "a.png", nil)
    {:ok, _} = Blog.attach_image(post, "b.png", nil)
    a = stored_file("a.png")
    b = stored_file("b.png")

    assert {:ok, _} = Blog.delete_post(post)
    refute File.exists?(a)
    refute File.exists?(b)
  end
end
