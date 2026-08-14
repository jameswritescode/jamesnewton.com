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

  test "count_entries/0 counts all; count_in_progress/0 counts reading + listening" do
    {:ok, _} = Reading.create_entry(%{title: "A", author: "x", status: :read})
    {:ok, _} = Reading.create_entry(%{title: "B", author: "y", status: :reading})
    {:ok, _} = Reading.create_entry(%{title: "C", author: "z", status: :listening})

    assert Reading.count_entries() == 3
    assert Reading.count_in_progress() == 2
  end

  test "get_entry!/1 returns the entry with the given id" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    assert Reading.get_entry!(entry.id).id == entry.id
  end

  test "update_entry/2 updates the given fields" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :reading})
    {:ok, updated} = Reading.update_entry(entry, %{title: "T2", status: :read})
    assert updated.title == "T2"
    assert updated.status == :read
  end

  test "delete_entry/1 removes the entry" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    {:ok, _} = Reading.delete_entry(entry)
    assert_raise Ecto.NoResultsError, fn -> Reading.get_entry!(entry.id) end
  end

  test "change_entry/1 returns a changeset" do
    {:ok, entry} = Reading.create_entry(%{title: "T", author: "A", status: :read})
    assert %Ecto.Changeset{} = Reading.change_entry(entry)
  end

  test "status_counts/0 returns a count per status, zero-filled" do
    {:ok, _} = Reading.create_entry(%{title: "A", author: "x", status: :read})
    {:ok, _} = Reading.create_entry(%{title: "B", author: "y", status: :read})
    {:ok, _} = Reading.create_entry(%{title: "C", author: "z", status: :reading})

    assert Reading.status_counts() == %{read: 2, reading: 1, listened: 0, listening: 0}
  end

  test "series is optional and blank normalizes to nil" do
    {:ok, blank} = Reading.create_entry(%{title: "T", author: "A", status: :read, series: "   "})
    assert blank.series == nil

    {:ok, trimmed} =
      Reading.create_entry(%{title: "T2", author: "A", status: :read, series: " First Law "})

    assert trimmed.series == "First Law"

    {:ok, cleared} = Reading.update_entry(trimmed, %{series: ""})
    assert cleared.series == nil
  end

  test "series_names/0 returns distinct sorted names excluding nil" do
    {:ok, _} = Reading.create_entry(%{title: "A", author: "x", status: :read, series: "Zeta"})
    {:ok, _} = Reading.create_entry(%{title: "B", author: "x", status: :read, series: "Alpha"})
    {:ok, _} = Reading.create_entry(%{title: "C", author: "x", status: :read, series: "Alpha"})
    {:ok, _} = Reading.create_entry(%{title: "D", author: "x", status: :read})

    assert Reading.series_names() == ["Alpha", "Zeta"]
  end

  describe "feed_entries/0" do
    defp entry!(title, opts) do
      {:ok, entry} =
        Reading.create_entry(%{
          title: title,
          author: Keyword.get(opts, :author, "A"),
          status: Keyword.get(opts, :status, :read),
          finished_at: Keyword.get(opts, :finished_at),
          series: Keyword.get(opts, :series)
        })

      entry
    end

    test "groups a series at its newest entry, newest first within the group" do
      entry!("Book 1", series: "Saga", finished_at: ~D[2026-02-01])
      entry!("Between", finished_at: ~D[2026-03-01])
      entry!("Book 2", series: "Saga", finished_at: ~D[2026-04-01])
      entry!("Oldest", finished_at: ~D[2026-01-01])

      assert [{:series, "Saga", [b2, b1]}, between, oldest] = Reading.feed_entries()
      assert b2.title == "Book 2"
      assert b1.title == "Book 1"
      assert between.title == "Between"
      assert oldest.title == "Oldest"
    end

    test "an in-progress series book floats the group to the top" do
      entry!("Newest standalone", finished_at: ~D[2026-05-01])
      entry!("Book 1", series: "Saga", finished_at: ~D[2026-01-01])
      entry!("Book 2", series: "Saga", status: :reading, finished_at: nil)

      assert [{:series, "Saga", [b2, b1]}, standalone] = Reading.feed_entries()
      assert b2.title == "Book 2"
      assert b1.title == "Book 1"
      assert standalone.title == "Newest standalone"
    end

    test "a singleton series renders as a plain entry" do
      entry!("Solo", series: "Saga", finished_at: ~D[2026-01-01])

      assert [%Newton.Reading.Entry{title: "Solo"}] = Reading.feed_entries()
    end

    test "entries without a series pass through in order" do
      entry!("Old", finished_at: ~D[2025-01-01])
      entry!("New", finished_at: ~D[2026-01-01])

      assert ["New", "Old"] = Reading.feed_entries() |> Enum.map(& &1.title)
    end
  end
end
