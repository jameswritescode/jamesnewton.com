defmodule Newton.SlugTest do
  use ExUnit.Case, async: true

  test "slugifies titles" do
    assert Newton.Slug.slugify("A Philosophy of Software Design") == "a-philosophy-of-software-design"
    assert Newton.Slug.slugify("Eastern Sierra!") == "eastern-sierra"
  end
end
