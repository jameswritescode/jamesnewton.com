defmodule Newton.Analytics.Collector do
  @moduledoc """
  Buffers public page views from Phoenix router telemetry and flushes them to
  Newton.Analytics as hourly rollups.
  """
  use GenServer
  require Logger

  alias Newton.Analytics

  @handler_id "newton-analytics-collector"
  @event [:phoenix, :router_dispatch, :stop]
  @public_routes ~w(/ /posts /posts/:slug /reading /photos /links /resume)
  @bot_ua ~r/bot|crawl|spider|slurp|curl|wget|python|java|httpclient|http.client|scan|monitor|probe|fetch|preview/i
  @flush_ms 10_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    :telemetry.detach(@handler_id)
    :ok = :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil)
    {:ok, %{buffer: %{}}, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_flush()
    {:noreply, state}
  end

  # Runs in the request process. Must never raise: :telemetry permanently
  # detaches a raising handler. Every clause falls through to "don't count".
  @spec handle_event(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def handle_event(_event, _measurements, metadata, _config) do
    with %{conn: conn, route: route} when route in @public_routes <- metadata,
         %Plug.Conn{method: "GET", status: 200} <- conn,
         false <- preview?(conn),
         false <- authenticated?(conn),
         true <- human?(conn) do
      GenServer.cast(__MODULE__, {:view, conn.request_path})
    else
      _ -> :ok
    end
  end

  defp preview?(%Plug.Conn{params: %{"p" => p}}) when not is_nil(p), do: true
  defp preview?(_conn), do: false

  defp authenticated?(%Plug.Conn{assigns: %{current_scope: %{user: %{}}}}), do: true
  defp authenticated?(_conn), do: false

  defp human?(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] when byte_size(ua) > 0 -> not Regex.match?(@bot_ua, ua)
      _ -> false
    end
  end

  @impl true
  def handle_cast({:view, path}, state) do
    hour = %{DateTime.utc_now(:second) | minute: 0, second: 0}
    key = {hour, path}
    {:noreply, %{state | buffer: Map.update(state.buffer, key, 1, &(&1 + 1))}}
  end

  @impl true
  def handle_info(:flush, state) do
    do_flush(state.buffer)
    schedule_flush()
    {:noreply, %{state | buffer: %{}}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    do_flush(state.buffer)
    {:reply, :ok, %{state | buffer: %{}}}
  end

  @impl true
  def terminate(_reason, state), do: do_flush(state.buffer)

  defp do_flush(buffer) when map_size(buffer) == 0, do: :ok

  defp do_flush(buffer) do
    Newton.Telemetry.span(:analytics, :flush, %{row_count: map_size(buffer)}, fn ->
      try do
        :ok = Analytics.record_views(buffer)
        {:ok, %{result: :ok, row_count: map_size(buffer)}}
      rescue
        e ->
          Logger.warning("analytics flush failed, dropping buffer: #{Exception.message(e)}")
          {:error, %{result: :error, row_count: map_size(buffer)}}
      end
    end)

    :ok
  end

  defp schedule_flush do
    case Application.get_env(:newton, __MODULE__, [])[:flush_interval] || @flush_ms do
      :manual -> :ok
      ms -> Process.send_after(self(), :flush, ms)
    end
  end
end
