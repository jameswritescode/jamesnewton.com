defmodule NewtonWeb.Admin.ReadingLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Reading

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp entry_fixture(attrs \\ %{}) do
    {:ok, entry} =
      attrs
      |> Enum.into(%{
        title: "A Book",
        author: "An Author",
        status: :read,
        finished_at: ~D[2026-01-01]
      })
      |> Reading.create_entry()

    entry
  end

  test "lists existing entries", %{conn: conn} do
    entry = entry_fixture(%{title: "Dune"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading")
    assert has_element?(view, "#entries-#{entry.id}", "Dune")
  end

  test "renders the finished-vs-in-progress summary", %{conn: conn} do
    entry_fixture(%{title: "Done", status: :read})
    entry_fixture(%{title: "Reading now", status: :reading, finished_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/reading")

    assert has_element?(view, "#reading-summary", "1 read · 1 reading")
  end

  test "Add entry opens the drawer in new mode", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading")

    view |> element("a", "Add entry") |> render_click()

    assert_patch(view, ~p"/admin/reading/new")
    assert has_element?(view, "#reading-drawer #reading-form")
  end

  test "creates an entry and shows it in the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    view
    |> form("#reading-form", entry: %{title: "New Book", author: "Auth", status: :reading})
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert has_element?(view, "#entries", "New Book")
    assert Enum.any?(Reading.list_entries(), &(&1.title == "New Book"))
  end

  test "shows validation errors on invalid submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    html =
      view
      |> form("#reading-form", entry: %{title: "", author: "", status: :reading})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "edits an existing entry", %{conn: conn} do
    entry = entry_fixture(%{title: "Old Title"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading/#{entry.id}/edit")

    view
    |> form("#reading-form", entry: %{title: "Updated Title"})
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert Reading.get_entry!(entry.id).title == "Updated Title"
  end

  test "Escape closes the drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")
    assert has_element?(view, "#reading-drawer")

    view |> element("#reading-drawer") |> render_keydown(%{"key" => "Escape"})

    assert_patch(view, ~p"/admin/reading")
    refute has_element?(view, "#reading-drawer")
  end

  test "the drawer closes on click-away", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")
    assert has_element?(view, "#reading-drawer[phx-click-away]")

    render_click(view, "close_drawer", %{})

    assert_patch(view, ~p"/admin/reading")
    refute has_element?(view, "#reading-drawer")
  end

  test "deletes an entry from the drawer", %{conn: conn} do
    entry = entry_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/reading/#{entry.id}/edit")

    view |> element("#reading-drawer button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/reading")
    assert_raise Ecto.NoResultsError, fn -> Reading.get_entry!(entry.id) end
  end

  test "creates an entry with a series", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    view
    |> form("#reading-form",
      entry: %{title: "New Book", author: "Auth", status: :read, series: "The Saga"}
    )
    |> render_submit()

    assert_patch(view, ~p"/admin/reading")
    assert Enum.any?(Reading.list_entries(), &(&1.series == "The Saga"))
  end

  test "series field suggests existing series names, including just-saved ones", %{conn: conn} do
    entry_fixture(%{title: "Earlier", series: "The Saga"})
    {:ok, view, _html} = live(conn, ~p"/admin/reading/new")

    assert has_element?(view, ~s(#series-names option[value="The Saga"]))
    refute has_element?(view, ~s(#series-names option[value="Fresh Series"]))

    view
    |> form("#reading-form",
      entry: %{title: "New Book", author: "Auth", status: :read, series: "Fresh Series"}
    )
    |> render_submit()

    view |> element("a", "Add entry") |> render_click()
    assert has_element?(view, ~s(#series-names option[value="Fresh Series"]))
  end
end
