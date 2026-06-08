defmodule Newton.Reading do
  @moduledoc "The reading context: books read/listened, newest first."
  import Ecto.Query, warn: false
  alias Newton.Repo
  alias Newton.Reading.Entry

  def create_entry(attrs) do
    %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
  end

  def list_entries do
    Repo.all(from e in Entry, order_by: [desc: e.finished_at])
  end

  def verb(:read), do: "Read"
  def verb(:reading), do: "Reading"
  def verb(:listened), do: "Listened to"
  def verb(:listening), do: "Listening to"
end
