defmodule Newton.ReadingTest do
  use Newton.DataCase
  alias Newton.Reading

  test "create_entry validates status enum" do
    {:error, cs} = Reading.create_entry(%{title: "T", author: "A", status: :bogus})
    assert %{status: _} = errors_on(cs)
  end

  test "list_entries orders by finished_at desc" do
    {:ok, _a} =
      Reading.create_entry(%{
        title: "Old",
        author: "A",
        status: :read,
        finished_at: ~D[2025-01-01]
      })

    {:ok, _b} =
      Reading.create_entry(%{
        title: "New",
        author: "B",
        status: :read,
        finished_at: ~D[2026-01-01]
      })

    assert Reading.list_entries() |> Enum.map(& &1.title) == ["New", "Old"]
  end

  test "verb/1 maps status to a display verb" do
    assert Reading.verb(:read) == "Read"
    assert Reading.verb(:reading) == "Reading"
    assert Reading.verb(:listened) == "Listened to"
    assert Reading.verb(:listening) == "Listening to"
  end

  test "recent_finished/1 excludes in-progress entries and limits to N" do
    {:ok, _} =
      Reading.create_entry(%{
        title: "In progress",
        author: "X",
        status: :reading,
        finished_at: nil
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Old",
        author: "A",
        status: :read,
        finished_at: ~D[2025-01-01]
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "New",
        author: "B",
        status: :read,
        finished_at: ~D[2026-01-01]
      })

    assert Reading.recent_finished(5) |> Enum.map(& &1.title) == ["New", "Old"]
    assert Reading.recent_finished(1) |> Enum.map(& &1.title) == ["New"]
  end
end
