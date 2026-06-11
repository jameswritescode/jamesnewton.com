defmodule Newton.Reading do
  @moduledoc "The reading context: books read/listened, newest first."
  import Ecto.Query, warn: false
  alias Newton.Reading.Entry
  alias Newton.Repo

  def create_entry(attrs) do
    %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
  end

  def get_entry!(id), do: Repo.get!(Entry, id)

  def update_entry(%Entry{} = entry, attrs) do
    entry |> Entry.changeset(attrs) |> Repo.update()
  end

  def delete_entry(%Entry{} = entry), do: Repo.delete(entry)

  def change_entry(%Entry{} = entry, attrs \\ %{}) do
    Entry.changeset(entry, attrs)
  end

  @statuses [:reading, :read, :listening, :listened]

  def status_counts do
    counted =
      Entry
      |> group_by([e], e.status)
      |> select([e], {e.status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    Map.new(@statuses, fn status -> {status, Map.get(counted, status, 0)} end)
  end

  def list_entries do
    Repo.all(from e in Entry, order_by: [desc: e.finished_at])
  end

  @doc "Total number of reading entries."
  def count_entries, do: Repo.aggregate(Entry, :count)

  @doc "Number of in-progress entries (currently reading or listening)."
  def count_in_progress do
    Repo.aggregate(from(e in Entry, where: e.status in [:reading, :listening]), :count)
  end

  @doc "Most recently finished entries (excluding in-progress), newest first, limited."
  def recent_finished(limit) do
    Repo.all(
      from e in Entry,
        where: not is_nil(e.finished_at),
        order_by: [desc: e.finished_at],
        limit: ^limit
    )
  end

  def verb(:read), do: "Read"
  def verb(:reading), do: "Reading"
  def verb(:listened), do: "Listened to"
  def verb(:listening), do: "Listening to"
end
