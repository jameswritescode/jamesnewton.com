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

  test "store/2 rejects a file whose bytes are not a supported image" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "<?php system($_GET['c']); ?>")

    assert {:error, :unsupported_content} = Storage.store(src, "totally.png")
    File.rm(src)
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
