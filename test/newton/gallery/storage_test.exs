defmodule Newton.Gallery.StorageTest do
  use ExUnit.Case, async: true
  alias Newton.Gallery.Storage

  @root Application.compile_env!(:newton, :media_root)

  setup do
    File.mkdir_p!(@root)
    :ok
  end

  test "store/2 copies the file under media_root and returns a key" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "imagedata")

    assert {:ok, key} = Storage.store(src, "photo.JPG")
    on_exit(fn -> File.rm(Path.join(@root, key)) end)

    assert String.ends_with?(key, ".jpg")
    assert File.read!(Path.join(@root, key)) == "imagedata"
    File.rm(src)
  end

  test "delete/1 removes the file and is idempotent" do
    src = Path.join(@root, "upload-#{System.unique_integer([:positive])}.tmp")
    File.write!(src, "data")
    {:ok, key} = Storage.store(src, "a.png")
    File.rm(src)

    assert :ok = Storage.delete(key)
    refute File.exists?(Path.join(@root, key))
    assert :ok = Storage.delete(key)
  end
end
