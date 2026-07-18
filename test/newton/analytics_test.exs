defmodule Newton.AnalyticsTest do
  use Newton.DataCase, async: true

  alias Newton.Analytics

  @la "America/Los_Angeles"
  @utc "Etc/UTC"

  test "record_views inserts new hourly buckets and increments existing ones" do
    hour = ~U[2026-07-18 12:00:00Z]

    :ok = Analytics.record_views(%{{hour, "/posts/hello"} => 2, {hour, "/photos"} => 1})
    :ok = Analytics.record_views(%{{hour, "/posts/hello"} => 3})

    assert Analytics.total_all_time() == 6
  end

  test "record_views with an empty map is a no-op" do
    assert Analytics.record_views(%{}) == :ok
    assert Analytics.total_all_time() == 0
  end

  test "daily_totals groups hours into the viewer's local days" do
    # 00:00 and 01:00 UTC on the 18th are still the evening of the 17th in LA.
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/a"} => 2,
        {~U[2026-07-18 01:00:00Z], "/posts/a"} => 3,
        {~U[2026-07-18 12:00:00Z], "/posts/a"} => 7
      })

    assert [%{date: ~D[2026-07-17], count: 5}, %{date: ~D[2026-07-18], count: 7}] =
             Analytics.daily_totals(~D[2026-07-01], @la)

    assert [%{date: ~D[2026-07-18], count: 12}] = Analytics.daily_totals(~D[2026-07-01], @utc)
  end

  test "the LA day boundary falls at the DST-correct UTC hour" do
    :ok =
      Analytics.record_views(%{
        # 06:00 UTC on the 18th = 23:00 PDT on the 17th; 07:00 UTC = 00:00 PDT on the 18th.
        {~U[2026-07-18 06:00:00Z], "/posts/a"} => 1,
        {~U[2026-07-18 07:00:00Z], "/posts/a"} => 2
      })

    assert [%{date: ~D[2026-07-17], count: 1}, %{date: ~D[2026-07-18], count: 2}] =
             Analytics.daily_totals(~D[2026-07-01], "America/Los_Angeles")
  end

  test "total_since applies the zone's day boundary to the window" do
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/a"} => 5,
        {~U[2026-07-18 12:00:00Z], "/posts/a"} => 7
      })

    assert Analytics.total_since(~D[2026-07-18], @utc) == 12
    assert Analytics.total_since(~D[2026-07-18], @la) == 7
  end

  test "top_paths filters by local day, orders by total, and honors the limit" do
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/old-evening"} => 9,
        {~U[2026-07-18 12:00:00Z], "/posts/b"} => 4,
        {~U[2026-07-18 13:00:00Z], "/posts/c"} => 6
      })

    assert [%{path: "/posts/c", count: 6}, %{path: "/posts/b", count: 4}] =
             Analytics.top_paths(~D[2026-07-18], 2, @la)
  end

  test "local_today returns the date in the given zone" do
    assert Analytics.local_today(@utc) == DateTime.utc_now() |> DateTime.to_date()
    assert %Date{} = Analytics.local_today(@la)
  end
end
