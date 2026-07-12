defmodule Newton.Blog.ImageAuditTest do
  use Newton.DataCase
  alias Newton.Blog
  alias Newton.Blog.ImageAudit

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    path = Path.join(media_root(), key)
    File.write!(path, "img-bytes")
    path
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

  test "extract_keys pulls unique /media/ keys from a body, nil-safe" do
    body = "![](/media/a.png) text ![](/media/b.jpg) again ![](/media/a.png)"
    assert ImageAudit.extract_keys(body) == ["a.png", "b.jpg"]
    assert ImageAudit.extract_keys(nil) == []
  end

  test "run reports missing keys and unowned strays" do
    post = post_with_body("![](/media/ghost.png)")
    stored_file("stray.png")

    assert %{missing: [{slug, "ghost.png"}], strays: ["stray.png"]} = ImageAudit.run()
    assert slug == post.slug
  end

  test "run ignores dotfiles on the volume" do
    stored_file(".keep")
    assert %{strays: []} = ImageAudit.run()
  end

  test "run does not list ledgered, gallery-owned, or body-referenced files as strays" do
    post = post_with_body("![](/media/ledgered.png) ![](/media/referenced.png)")
    {:ok, _} = Blog.attach_image(post, "ledgered.png", nil)

    group = Newton.GalleryFixtures.group_fixture()
    photo = Newton.GalleryFixtures.photo_fixture(group)

    stored_file("ledgered.png")
    stored_file("referenced.png")
    stored_file(photo.image_key)

    assert %{strays: []} = ImageAudit.run()
  end

  test "delete_stray removes a true stray's file" do
    path = stored_file("stray.png")

    assert :ok = ImageAudit.delete_stray("stray.png")
    refute File.exists?(path)
  end

  test "delete_stray refuses owned or referenced keys" do
    post = post_with_body("![](/media/referenced.png)")
    {:ok, _} = Blog.attach_image(post, "ledgered.png", nil)
    referenced = stored_file("referenced.png")
    ledgered = stored_file("ledgered.png")

    assert {:error, :not_stray} = ImageAudit.delete_stray("referenced.png")
    assert {:error, :not_stray} = ImageAudit.delete_stray("ledgered.png")
    assert File.exists?(referenced)
    assert File.exists?(ledgered)
  end
end
