defmodule Newton.PromExTest do
  use NewtonWeb.ConnCase, async: false

  test "the shared IndexNow metric appears in the scrape after its event fires" do
    duration = System.convert_time_unit(120, :millisecond, :native)

    :telemetry.execute(
      [:newton, :indexnow, :submit, :stop],
      %{duration: duration},
      %{result: :ok, status: 200, url_count: 2}
    )

    metrics = PromEx.get_metrics(Newton.PromEx)

    assert metrics =~ "newton_indexnow_submit_stop_duration"
    assert metrics =~ ~s(result="ok")
  end

  test "a request through the endpoint lands in the Phoenix plugin's series", %{conn: conn} do
    get(conn, ~p"/")

    assert PromEx.get_metrics(Newton.PromEx) =~ "phoenix_"
  end
end
