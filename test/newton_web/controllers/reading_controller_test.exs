defmodule NewtonWeb.ReadingControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Reading

  test "GET /reading lists entries with the right verb and cite", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "A Philosophy of Software Design",
        author: "John Ousterhout",
        status: :read,
        finished_at: ~D[2026-04-18],
        note: "The argument for deep modules stuck with me."
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    assert html =~ "Read"
    assert html =~ "<cite>A Philosophy of Software Design</cite>"
    assert html =~ "John Ousterhout"
    assert html =~ "deep modules"
  end

  test "GET /reading groups series entries under a shared-author label", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "Book One",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-01-10],
        series: "The Saga"
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Standalone",
        author: "Someone Else",
        status: :read,
        finished_at: ~D[2026-02-10]
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Book Two",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-03-10],
        series: "The Saga"
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    series = html |> LazyHTML.from_document() |> LazyHTML.query(".feed-series") |> LazyHTML.text()

    assert series =~ "Book One"
    assert series =~ "Book Two"
    assert series =~ "The Saga · Ann Author"
    refute series =~ "Standalone"
    refute series =~ "by Ann Author"
  end

  test "GET /reading keeps per-entry authors when a series has several", %{conn: conn} do
    {:ok, _} =
      Reading.create_entry(%{
        title: "Book One",
        author: "Ann Author",
        status: :read,
        finished_at: ~D[2026-01-10],
        series: "The Saga"
      })

    {:ok, _} =
      Reading.create_entry(%{
        title: "Book Two",
        author: "Bob Writer",
        status: :read,
        finished_at: ~D[2026-03-10],
        series: "The Saga"
      })

    html = conn |> get(~p"/reading") |> html_response(200)
    series = html |> LazyHTML.from_document() |> LazyHTML.query(".feed-series") |> LazyHTML.text()

    assert series =~ "by Ann Author"
    assert series =~ "by Bob Writer"
    refute series =~ "The Saga ·"
  end
end
