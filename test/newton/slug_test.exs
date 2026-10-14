defmodule Newton.SlugTest do
  use ExUnit.Case, async: true

  alias Newton.Slug

  test "slugifies titles" do
    assert Slug.slugify("A Philosophy of Software Design") ==
             "a-philosophy-of-software-design"

    assert Slug.slugify("Eastern Sierra!") == "eastern-sierra"
  end

  describe "first_free/2" do
    test "starts the series at the bare prefix" do
      assert Slug.first_free("untitled-page", []) == "untitled-page"
    end

    test "takes the first gap in the numbered series" do
      taken = ~w(untitled-page untitled-page-2 untitled-page-4)
      assert Slug.first_free("untitled-page", taken) == "untitled-page-3"
    end

    test "ignores slugs that only share the prefix" do
      taken = ~w(untitled-pages-of-history untitled-page-of-x untitled-page-2b)
      assert Slug.first_free("untitled-page", taken) == "untitled-page"
    end
  end

  test "in_sequence?/2 accepts only the prefix and its numbered forms" do
    assert Slug.in_sequence?("untitled-post", "untitled-post")
    assert Slug.in_sequence?("untitled-post-12", "untitled-post")
    refute Slug.in_sequence?("untitled-posts", "untitled-post")
    refute Slug.in_sequence?("untitled-post-draft", "untitled-post")
  end
end
