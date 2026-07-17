defmodule Newton.IndexNowTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Newton.IndexNow

  @urls ["http://localhost:4002/posts/hello", "http://localhost:4002/posts"]

  defp enable do
    config = Application.get_env(:newton, IndexNow)
    Application.put_env(:newton, IndexNow, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, IndexNow, config) end)
  end

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :indexnow, :submit, :stop]])
    %{ref: ref}
  end

  test "submits host, key, and urlList to the API", %{ref: ref} do
    enable()
    test_pid = self()

    Req.Test.stub(IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    assert IndexNow.submit(@urls) == :ok

    assert_received {:request, request}
    assert request["host"] == "localhost"
    assert request["key"] == "d1258f1d59aea5c8f3e604eb494cc477"
    assert request["urlList"] == @urls

    assert_received {[:newton, :indexnow, :submit, :stop], ^ref, %{duration: _},
                     %{result: :ok, status: 200, url_count: 2}}
  end

  test "non-2xx responses return an error, log, and mark the span", %{ref: ref} do
    enable()
    Req.Test.stub(IndexNow, fn conn -> Plug.Conn.send_resp(conn, 422, "") end)

    log =
      capture_log(fn ->
        assert IndexNow.submit(@urls) == {:error, {:status, 422}}
      end)

    assert log =~ "IndexNow"

    assert_received {[:newton, :indexnow, :submit, :stop], ^ref, %{duration: _},
                     %{result: :error, status: 422, url_count: 2}}
  end

  test "transport errors return an error, log, and mark the span", %{ref: ref} do
    enable()
    Req.Test.stub(IndexNow, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log(fn ->
        assert {:error, %Req.TransportError{reason: :econnrefused}} = IndexNow.submit(@urls)
      end)

    assert log =~ "IndexNow"

    assert_received {[:newton, :indexnow, :submit, :stop], ^ref, %{duration: _},
                     %{result: :error, status: nil, url_count: 2}}
  end

  test "no-ops when disabled", %{ref: ref} do
    assert IndexNow.submit(@urls) == :ok
    refute_received {[:newton, :indexnow, :submit, :stop], ^ref, _, _}
  end

  test "an empty url list is a no-op", %{ref: ref} do
    enable()
    assert IndexNow.submit([]) == :ok
    refute_received {[:newton, :indexnow, :submit, :stop], ^ref, _, _}
  end
end
