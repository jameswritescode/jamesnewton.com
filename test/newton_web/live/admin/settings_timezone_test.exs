defmodule NewtonWeb.Admin.SettingsTimezoneTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures
  import Newton.DataCase, only: [errors_on: 1]

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the timezone select shows the current value and saves a new one", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(view, ~s(#timezone-form option[selected][value="America/Los_Angeles"]))

    view
    |> form("#timezone-form", user: %{timezone: "Europe/Lisbon"})
    |> render_submit()

    assert render(view) =~ "Timezone updated"
    assert Newton.Repo.get!(Newton.Accounts.User, user.id).timezone == "Europe/Lisbon"
  end

  test "an unknown timezone is rejected", %{conn: conn, user: user} do
    {:ok, _view, _html} = live(conn, ~p"/admin/settings")

    assert {:error, changeset} =
             Newton.Accounts.update_user_timezone(user, %{"timezone" => "Mars/Olympus_Mons"})

    assert %{timezone: ["is not a known timezone"]} = errors_on(changeset)
  end
end
