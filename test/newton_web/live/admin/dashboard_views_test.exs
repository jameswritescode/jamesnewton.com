defmodule NewtonWeb.Admin.DashboardViewsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Analytics

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp la_hour(date, hour) do
    DateTime.new!(date, Time.new!(hour, 0, 0), "America/Los_Angeles")
    |> DateTime.shift_zone!("Etc/UTC")
    |> then(&%{&1 | minute: 0, second: 0})
  end

  defp seed_views do
    today = Newton.Analytics.local_today("America/Los_Angeles")

    {:ok, _} =
      Newton.Blog.create_post(%{
        slug: "top-post",
        title: "The Top Post",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    :ok =
      Analytics.record_views(%{
        {la_hour(today, 12), "/posts/top-post"} => 7,
        {la_hour(today, 13), "/posts/deleted-post"} => 3,
        {la_hour(Date.add(today, -30), 12), "/photos"} => 10
      })
  end

  test "the Views card shows 7-day and all-time totals", %{conn: conn} do
    seed_views()

    {:ok, view, _html} = live(conn, ~p"/admin")

    # 7-day total is 10 (7 + 3; the /photos views are 30 days old), all-time 20.
    assert has_element?(view, "#card-views", "10")
    assert has_element?(view, "#card-views", "20 all-time")
  end

  test "top posts list shows titles with counts and falls back to the raw path", %{conn: conn} do
    seed_views()

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#top-posts", "The Top Post")
    assert has_element?(view, "#top-posts", "/posts/deleted-post")
    refute has_element?(view, ~s(#top-posts a[href="/posts/deleted-post"]))
  end

  test "no views yet renders the card with zeros and no top-posts list", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin")

    assert has_element?(view, "#card-views")
    assert html =~ "0 all-time"
    refute has_element?(view, "#top-posts")
    assert has_element?(view, "#views-week", "No views yet this week")
  end

  test "the week panel summarizes the busiest day and daily average", %{conn: conn} do
    today = Newton.Analytics.local_today("America/Los_Angeles")
    elapsed_days = Date.diff(today, Date.beginning_of_week(today)) + 1

    :ok = Analytics.record_views(%{{la_hour(today, 12), "/posts/busy"} => 14})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#views-week", Calendar.strftime(today, "%A"))
    assert has_element?(view, "#views-week", "#{div(14, elapsed_days)}/day average")
  end

  test "the Views card is informational, not a link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "div#card-views")
    refute has_element?(view, "a#card-views")
  end
end
