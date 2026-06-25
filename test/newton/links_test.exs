defmodule Newton.LinksTest do
  use ExUnit.Case, async: true
  alias Newton.Links

  test "all/0 is led by GITHUB (the readout default)" do
    assert Links.all() |> List.first() |> Map.fetch!(:name) == "GITHUB"
  end

  test "all/0 includes each launch link" do
    names = Links.all() |> Enum.map(& &1.name)

    for expected <- ["GITHUB", "LINKEDIN", "BLUESKY", "MARK OS", "EMAIL"] do
      assert expected in names
    end
  end

  test "each link has a name, url, and description" do
    for link <- Links.all() do
      assert is_binary(link.name) and link.name != ""
      assert is_binary(link.url) and link.url != ""
      assert is_binary(link.description) and link.description != ""
    end
  end

  test "external?/1 is true for http(s) urls and false for mailto and paths" do
    assert Links.external?("https://github.com/jameswritescode")
    assert Links.external?("http://example.com")
    refute Links.external?("mailto:hello@jamesnewton.com")
    refute Links.external?("/")
  end
end
