defmodule Newton.Reading do
  @moduledoc "The reading context: books read/listened, newest first."
  import Ecto.Query, warn: false
  alias Newton.Reading.Entry
  alias Newton.Repo

  def create_entry(attrs) do
    %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
  end

  def list_entries do
    Repo.all(from e in Entry, order_by: [desc: e.finished_at])
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
