defmodule NewtonWeb.UserLive.VerifyTest do
  use NewtonWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  test "redirects to /login when there is no pending second factor", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/login/verify")
  end

  test "renders the verify page and the recovery form when pending", %{conn: conn} do
    user = set_password(user_fixture())

    conn = Plug.Test.init_test_session(conn, %{"pending_2fa_user_id" => user.id})
    {:ok, view, html} = live(conn, ~p"/login/verify")
    assert html =~ "passkey"
    assert html =~ "recovery code"

    html = view |> element("button[phx-click='show_recovery']") |> render_click()
    assert html =~ ~s(action="/login/verify/recovery")
  end
end
