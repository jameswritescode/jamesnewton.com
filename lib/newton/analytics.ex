defmodule Newton.Analytics do
  @moduledoc """
  Server-side view analytics: hourly UTC rollups, grouped into days in the
  viewer's timezone at query time.
  """
  import Ecto.Query

  alias Newton.Analytics.HourlyView
  alias Newton.Repo

  defmacrop local_date(hour, tz) do
    quote do
      fragment("((? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date", unquote(hour), unquote(tz))
    end
  end

  @spec record_views(%{optional({DateTime.t(), String.t()}) => pos_integer()}) :: :ok
  def record_views(counts) when map_size(counts) == 0, do: :ok

  def record_views(counts) do
    now = DateTime.utc_now(:second)

    rows =
      for {{hour, path}, count} <- counts do
        %{hour: hour, path: path, count: count, inserted_at: now, updated_at: now}
      end

    Repo.insert_all(HourlyView, rows,
      conflict_target: [:hour, :path],
      on_conflict:
        from(h in HourlyView,
          update: [
            inc: [count: fragment("EXCLUDED.count")],
            set: [updated_at: fragment("EXCLUDED.updated_at")]
          ]
        )
    )

    :ok
  end

  @spec local_today(String.t()) :: Date.t()
  def local_today(tz), do: tz |> DateTime.now!() |> DateTime.to_date()

  @spec total_since(Date.t(), String.t()) :: non_neg_integer()
  def total_since(date, tz) do
    Repo.one(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^date,
        select: coalesce(sum(h.count), 0)
    )
  end

  @spec total_all_time() :: non_neg_integer()
  def total_all_time do
    Repo.one(from h in HourlyView, select: coalesce(sum(h.count), 0))
  end

  @spec top_paths(Date.t(), pos_integer(), String.t()) ::
          [%{path: String.t(), count: non_neg_integer()}]
  def top_paths(since, limit, tz) do
    Repo.all(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^since,
        group_by: h.path,
        order_by: [desc: sum(h.count)],
        limit: ^limit,
        select: %{path: h.path, count: sum(h.count)}
    )
  end

  @spec daily_totals(Date.t(), String.t()) :: [%{date: Date.t(), count: non_neg_integer()}]
  def daily_totals(since, tz) do
    Repo.all(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^since,
        group_by: selected_as(:date),
        order_by: selected_as(:date),
        select: %{date: selected_as(local_date(h.hour, ^tz), :date), count: sum(h.count)}
    )
  end
end
