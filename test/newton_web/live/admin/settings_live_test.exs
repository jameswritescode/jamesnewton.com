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

  defp connected_oauth_client(name) do
    alias Newton.OAuth

    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => name,
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
        "token_endpoint_auth_method" => "none"
      })

    verifier = OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    {:ok, code} =
      OAuth.issue_code(
        client,
        "https://claude.ai/api/mcp/auth_callback",
        challenge,
        OAuth.canonical_resource()
      )

    {:ok, tokens} =
      OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

    {client, tokens}
  end

  test "lists connected apps", %{conn: conn} do
    {client, _tokens} = connected_oauth_client("Claude Code (newton)")

    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(view, "#connected-app-#{client.id}", "Claude Code (newton)")
  end

  test "shows the empty state when nothing is connected", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "No apps have access."
  end

  test "revoking a client removes it and kills its tokens", %{conn: conn} do
    {client, tokens} = connected_oauth_client("Doomed app")
    assert {:ok, _} = Newton.OAuth.verify_access_token(tokens.access_token)

    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    view
    |> element("#connected-app-#{client.id} button", "Revoke")
    |> render_click()

    refute has_element?(view, "#connected-app-#{client.id}")
    assert has_element?(view, "#connected-apps-empty")
    assert {:error, :invalid_token} = Newton.OAuth.verify_access_token(tokens.access_token)
  end

  test "a stale sudo window blocks revoking a client", %{conn: conn} do
    {client, tokens} = connected_oauth_client("Protected app")

    {:ok, view, _} = live(conn, ~p"/admin/settings")
    expire_sudo_window(view)

    render_click(view, "revoke_client", %{"id" => to_string(client.id)})

    assert_redirect(view, ~p"/login/confirm-access")
    assert {:ok, _} = Newton.OAuth.verify_access_token(tokens.access_token)
  end
end
