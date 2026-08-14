defmodule Newton.Gallery.StorageTest do
  use ExUnit.Case, async: true
  alias Newton.Gallery.Storage

  @root Application.compile_env!(:newton, :media_root)

  setup do
    File.mkdir_p!(@root)
    :ok
  end

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, "the rest of a jpeg">>
  @png <<0x89, "PNG\r\n", 0x1A, 0x0A, "the rest of a png">>

  test "store/2 copies the file under media_root and returns a key" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, @jpeg)

    assert {:ok, key} = Storage.store(src, "photo.JPG")
    on_exit(fn -> File.rm(Path.join(@root, key)) end)

    assert String.ends_with?(key, ".jpg")
    assert File.read!(Path.join(@root, key)) == @jpeg
    File.rm(src)
  end

  @gif <<"GIF89a", "the rest of a gif">>
  @webp <<"RIFF", 0, 0, 0, 0, "WEBP", "the rest of a webp">>

  test "store/2 names the file from its verified bytes, not the client extension" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, <<"GIF89a", "<script>alert(1)</script>">>)

    assert {:ok, key} = Storage.store(src, "pwn.html")
    on_exit(fn -> File.rm(Path.join(@root, key)) end)

    assert String.ends_with?(key, ".gif")
    refute String.ends_with?(key, ".html")
    File.rm(src)
  end

  test "store/2 derives the extension for every supported format" do
    for {bytes, ext} <- [{@jpeg, ".jpg"}, {@png, ".png"}, {@gif, ".gif"}, {@webp, ".webp"}] do
      src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
      File.write!(src, bytes)

      assert {:ok, key} = Storage.store(src, "anything.exe")
      on_exit(fn -> File.rm(Path.join(@root, key)) end)

      assert String.ends_with?(key, ext)
      File.rm(src)
    end
  end

  test "store/2 rejects a file whose bytes are not a supported image" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "<?php system($_GET['c']); ?>")

    assert {:error, :unsupported_content} = Storage.store(src, "totally.png")
    File.rm(src)
  end

  test "delete/1 refuses keys that would escape the media root" do
    name = "outside-#{System.unique_integer([:positive])}.txt"
    outside = Path.join(System.tmp_dir!(), name)

    for key <- ["../" <> name, "sub/../../" <> name, outside] do
      File.write!(outside, "do not delete me")

      assert Storage.delete(key) == :ok
      assert File.exists?(outside), "delete/1 followed #{inspect(key)} out of media_root"
    end

    File.rm(outside)
  end

  test "delete/1 removes the file and is idempotent" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, @png)
    {:ok, key} = Storage.store(src, "a.png")
    File.rm(src)

    assert :ok = Storage.delete(key)
    refute File.exists?(Path.join(@root, key))
    assert :ok = Storage.delete(key)
  end
end
