defmodule Newton.Reading do
  @moduledoc "The reading context: books read/listened, newest first."
  import Ecto.Query, warn: false
  alias Newton.Reading.Entry
  alias Newton.Repo

  @spec create_entry(map()) :: {:ok, %Entry{}} | {:error, Ecto.Changeset.t()}
  def create_entry(attrs) do
    %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
  end

  @spec get_entry!(integer()) :: %Entry{}
  def get_entry!(id), do: Repo.get!(Entry, id)

  @spec update_entry(%Entry{}, map()) :: {:ok, %Entry{}} | {:error, Ecto.Changeset.t()}
  def update_entry(%Entry{} = entry, attrs) do
    entry |> Entry.changeset(attrs) |> Repo.update()
  end

  @spec delete_entry(%Entry{}) :: {:ok, %Entry{}} | {:error, Ecto.Changeset.t()}
  def delete_entry(%Entry{} = entry), do: Repo.delete(entry)

  @spec change_entry(%Entry{}, map()) :: Ecto.Changeset.t()
  def change_entry(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  @doc "Distinct series names in use, sorted, for the admin autocomplete."
  @spec series_names() :: [String.t()]
  def series_names do
    Repo.all(
      from e in Entry,
        where: not is_nil(e.series),
        distinct: true,
        order_by: e.series,
        select: e.series
    )
  end

  @statuses [:reading, :read, :listening, :listened]

  @spec status_counts() :: %{
          read: non_neg_integer(),
          reading: non_neg_integer(),
          listened: non_neg_integer(),
          listening: non_neg_integer()
        }
  def status_counts do
    counted =
      Entry
      |> group_by([e], e.status)
      |> select([e], {e.status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    Map.new(@statuses, fn status -> {status, Map.get(counted, status, 0)} end)
  end

  @spec list_entries() :: [%Entry{}]
  def list_entries do
    Repo.all(from e in Entry, order_by: [desc_nulls_first: e.finished_at, desc: e.id])
  end

  @doc "Total number of reading entries."
  @spec count_entries() :: non_neg_integer()
  def count_entries, do: Repo.aggregate(Entry, :count)

  @doc "Number of in-progress entries (currently reading or listening)."
  @spec count_in_progress() :: non_neg_integer()
  def count_in_progress do
    Repo.aggregate(from(e in Entry, where: e.status in [:reading, :listening]), :count)
  end

  @doc "Most recently finished entries (excluding in-progress), newest first, limited."
  @spec recent_finished(non_neg_integer()) :: [%Entry{}]
  def recent_finished(limit) do
    Repo.all(
      from e in Entry,
        where: not is_nil(e.finished_at),
        order_by: [desc: e.finished_at],
        limit: ^limit
    )
  end

  @type feed_item :: %Entry{} | {:series, String.t(), [%Entry{}]}

  @doc """
  Public reading feed: `list_entries/0` order, but all entries of a series are
  pulled together into a `{:series, name, entries}` tuple positioned where the
  series' newest entry falls. Singleton series stay plain entries.
  """
  @spec feed_entries() :: [feed_item()]
  def feed_entries do
    entries = list_entries()

    groups =
      entries
      |> Enum.reject(&is_nil(&1.series))
      |> Enum.group_by(& &1.series)

    entries
    |> Enum.reduce({[], MapSet.new()}, fn entry, {acc, seen} ->
      cond do
        is_nil(entry.series) -> {[entry | acc], seen}
        MapSet.member?(seen, entry.series) -> {acc, seen}
        true -> {[feed_group(entry.series, groups) | acc], MapSet.put(seen, entry.series)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp feed_group(series, groups) do
    case groups[series] do
      [single] -> single
      group -> {:series, series, group}
    end
  end

  @spec verb(:read | :reading | :listened | :listening) :: String.t()
  def verb(:read), do: "Read"
  def verb(:reading), do: "Reading"
  def verb(:listened), do: "Listened to"
  def verb(:listening), do: "Listening to"
end
