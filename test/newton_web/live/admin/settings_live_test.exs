defmodule NewtonWeb.Admin.SettingsLiveTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture() |> set_password()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp expire_sudo_window(view) do
    :sys.replace_state(view.pid, fn state ->
      update_in(state.socket.assigns.user, fn user ->
        %{user | authenticated_at: DateTime.add(DateTime.utc_now(), -60, :minute)}
      end)
    end)
  end

  test "a stale sudo window blocks regenerating recovery codes", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")
    expire_sudo_window(view)

    render_click(view, "generate_recovery_codes", %{})

    assert_redirect(view, ~p"/login/confirm-access")
    assert Newton.Accounts.count_unused_recovery_codes(user) == 0
  end

  test "a stale sudo window blocks deleting a passkey", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/settings")
    expire_sudo_window(view)

    render_click(view, "delete_passkey", %{"id" => "1"})

    assert_redirect(view, ~p"/login/confirm-access")
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

  test "recovery codes section is hidden without a passkey and shown with one", %{
    conn: conn,
    user: user
  } do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")
    refute html =~ "Recovery codes"

    {:ok, _} =
      Newton.Accounts.create_credential(user, %{
        credential_id: <<3, 3, 3>>,
        public_key: :erlang.term_to_binary(%{1 => 2}),
        sign_count: 0,
        label: "K"
      })

    {:ok, view, html} = live(conn, ~p"/admin/settings")
    assert html =~ "Recovery codes"

    html = view |> element("button", "Generate recovery codes") |> render_click()
    assert length(Regex.scan(~r/[A-Z0-9]{5}-[A-Z0-9]{5}/, html)) == 10
    assert Newton.Accounts.count_unused_recovery_codes(user) == 10

    # the button now offers to regenerate
    assert has_element?(view, "button", "Regenerate recovery codes")
  end
end
