defmodule NewtonWeb.Admin.SettingsLiveTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture() |> set_password()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "renders the settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "Change password"
    assert html =~ "Passkeys"
  end

  test "a wrong current password shows an error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")

    html =
      view
      |> form("#password-form", %{
        current_password: "nope",
        user: %{password: "a brand new password", password_confirmation: "a brand new password"}
      })
      |> render_submit()

    assert html =~ "is not valid"
  end

  test "the correct current password changes it", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")

    view
    |> form("#password-form", %{
      current_password: valid_user_password(),
      user: %{password: "a brand new password", password_confirmation: "a brand new password"}
    })
    |> render_submit()

    assert Newton.Accounts.get_user_by_email_and_password(user.email, "a brand new password")
  end

  test "lists and deletes passkeys", %{conn: conn, user: user} do
    {:ok, cred} =
      Newton.Accounts.create_credential(user, %{
        credential_id: <<9, 9, 9>>,
        public_key: :erlang.term_to_binary(%{1 => 2}),
        sign_count: 0,
        label: "My Laptop"
      })

    {:ok, view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "My Laptop"

    view |> element("button[phx-value-id='#{cred.id}']") |> render_click()
    refute render(view) =~ "My Laptop"
  end
end
