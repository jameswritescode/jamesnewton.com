defmodule Newton.Analytics.CollectorTest do
  use NewtonWeb.ConnCase, async: false

  alias Newton.Analytics
  alias Newton.Analytics.Collector

  import Newton.AccountsFixtures

  @ua {"user-agent", "TestBrowser/1.0"}

  setup do
    Ecto.Adapters.SQL.Sandbox.allow(Newton.Repo, self(), Process.whereis(Collector))
    Collector.flush()
    :ok
  end

  defp browse(conn, path, headers \\ [@ua]) do
    Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end) |> get(path)
  end

  defp count_for(path) do
    Analytics.top_paths(Date.add(Date.utc_today(), -2), 100, "Etc/UTC")
    |> Enum.find_value(0, fn %{path: p, count: c} -> if p == path, do: c end)
  end

  defp published_post(slug) do
    {:ok, post} =
      Newton.Blog.create_post(%{
        slug: slug,
        title: "Post #{slug}",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    post
  end

  test "percent-encoded and duplicate-slash requests count under one canonical path", %{
    conn: conn
  } do
    published_post("canon")

    browse(conn, "/posts/canon")
    browse(conn, "/posts/%63anon")
    browse(conn, "/posts/can%6Fn")
    Collector.flush()

    assert count_for("/posts/canon") == 3
    assert count_for("/posts/%63anon") == 0
    assert count_for("/posts/can%6Fn") == 0
  end

  test "duplicate slashes on the home route collapse to one path", %{conn: conn} do
    browse(conn, "/")
    browse(conn, "//")
    browse(conn, "///")
    Collector.flush()

    assert count_for("/") == 3
    assert count_for("//") == 0
    assert count_for("///") == 0
  end

  test "a public page view lands in hourly_views and repeats increment", %{conn: conn} do
    published_post("count-me")

    browse(conn, "/posts/count-me")
    Collector.flush()
    assert count_for("/posts/count-me") == 1

    browse(conn, "/posts/count-me")
    Collector.flush()
    assert count_for("/posts/count-me") == 2
  end

  test "bot user-agents are not counted", %{conn: conn} do
    published_post("bot-bait")

    browse(conn, "/posts/bot-bait", [{"user-agent", "Mozilla/5.0 (compatible; Googlebot/2.1)"}])
    Collector.flush()

    assert count_for("/posts/bot-bait") == 0
  end

  test "requests without a user-agent are not counted", %{conn: conn} do
    published_post("no-ua")

    get(conn, "/posts/no-ua")
    Collector.flush()

    assert count_for("/posts/no-ua") == 0
  end

  test "preview-token requests are not counted", %{conn: conn} do
    published_post("previewed")

    browse(conn, "/posts/previewed?p=sometoken")
    Collector.flush()

    assert count_for("/posts/previewed") == 0
  end

  test "authenticated sessions are not counted", %{conn: conn} do
    published_post("own-visit")

    conn |> log_in_user(user_fixture()) |> browse("/posts/own-visit")
    Collector.flush()

    assert count_for("/posts/own-visit") == 0
  end

  test "non-public routes are not counted", %{conn: conn} do
    browse(conn, "/sitemap.xml")
    Collector.flush()

    assert count_for("/sitemap.xml") == 0
  end

  test "404s are not counted", %{conn: conn} do
    assert_error_sent 404, fn -> browse(conn, "/posts/nope") end
    Collector.flush()

    assert count_for("/posts/nope") == 0
  end

  test "flush emits the analytics telemetry span" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :analytics, :flush, :stop]])

    send(Process.whereis(Collector), {:"$gen_cast", {:view, "/posts/span-check"}})
    Collector.flush()

    assert_received {[:newton, :analytics, :flush, :stop], ^ref, %{duration: _},
                     %{result: :ok, row_count: 1}}
  end
end
