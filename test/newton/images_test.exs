defmodule Newton.ImagesTest do
  use ExUnit.Case, async: true
  alias Newton.Images

  test "referenced? is true when the body contains the key" do
    assert Images.referenced?("see ![](/media/abc.png)", "abc.png")
  end

  test "referenced? is false when the body does not contain the key" do
    refute Images.referenced?("no images here", "abc.png")
  end

  test "referenced? treats a nil body as empty" do
    refute Images.referenced?(nil, "abc.png")
  end
end
