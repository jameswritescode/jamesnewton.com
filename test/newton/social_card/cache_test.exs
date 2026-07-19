defmodule Newton.SocialCard.CacheTest do
  use ExUnit.Case, async: false

  alias Newton.SocialCard.Cache

  test "renders on a miss and serves the cached bytes on a version match" do
    slug = "cache-#{System.unique_integer([:positive])}"
    calls = :counters.new(1, [])

    render = fn ->
      :counters.add(calls, 1, 1)
      {:ok, "png-bytes"}
    end

    assert {:ok, "png-bytes"} = Cache.fetch(slug, ~U[2026-07-19 00:00:00Z], render)
    assert {:ok, "png-bytes"} = Cache.fetch(slug, ~U[2026-07-19 00:00:00Z], render)
    assert :counters.get(calls, 1) == 1
  end

  test "re-renders when the version changes" do
    slug = "cache-#{System.unique_integer([:positive])}"

    assert {:ok, "v1"} = Cache.fetch(slug, ~U[2026-07-19 00:00:00Z], fn -> {:ok, "v1"} end)
    assert {:ok, "v2"} = Cache.fetch(slug, ~U[2026-07-19 09:00:00Z], fn -> {:ok, "v2"} end)
  end

  test "does not cache a render error" do
    slug = "cache-#{System.unique_integer([:positive])}"

    assert {:error, :boom} = Cache.fetch(slug, 1, fn -> {:error, :boom} end)
    assert {:ok, "recovered"} = Cache.fetch(slug, 1, fn -> {:ok, "recovered"} end)
  end
end
