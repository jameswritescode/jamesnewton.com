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
end
