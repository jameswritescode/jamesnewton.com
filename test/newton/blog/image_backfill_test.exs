defmodule Newton.Blog.ImageBackfillTest do
  use Newton.DataCase
  alias Newton.Blog
  alias Newton.Blog.ImageBackfill

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    File.write!(Path.join(media_root(), key), "img-bytes")
  end

  defp post_with_body(body) do
    {:ok, post} =
      Blog.create_post(%{
        slug: "post-#{System.unique_integer([:positive])}",
        title: "A Post",
        body_markdown: body
      })

    post
  end

  setup do
    File.rm_rf!(media_root())
    File.mkdir_p!(media_root())
    :ok
  end

  test "adopts referenced on-volume files, skipping already-tracked ones" do
    post = post_with_body("![](/media/wild.png) and ![](/media/tracked.png)")
    {:ok, _} = Blog.attach_image(post, "tracked.png", nil)
    stored_file("wild.png")
    stored_file("tracked.png")

    report = ImageBackfill.run()

    assert report.adopted == ["wild.png"]

    assert Enum.map(Blog.list_images(post), & &1.key) |> Enum.sort() ==
             ["tracked.png", "wild.png"]
  end

  test "never adopts gallery photo keys" do
    group = Newton.GalleryFixtures.group_fixture()
    photo = Newton.GalleryFixtures.photo_fixture(group)
    post = post_with_body("![](/media/#{photo.image_key})")
    stored_file(photo.image_key)

    report = ImageBackfill.run()

    assert report.adopted == []
    assert Blog.list_images(post) == []
  end

  test "is idempotent" do
    post_with_body("![](/media/wild.png)")
    stored_file("wild.png")

    assert %{adopted: ["wild.png"]} = ImageBackfill.run()
    assert %{adopted: []} = ImageBackfill.run()
  end
end
