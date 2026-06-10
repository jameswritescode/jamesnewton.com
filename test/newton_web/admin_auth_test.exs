defmodule NewtonWeb.AdminAuthTest do
  use NewtonWeb.ConnCase, async: true

  import Newton.AccountsFixtures

  describe "registration is disabled" do
    test "GET /users/register returns 404", %{conn: conn} do
      conn = get(conn, "/users/register")
      assert conn.status == 404
    end
  end

  describe "admin scope is gated" do
    test "redirects anonymous users from /admin to log-in", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "lets a signed-in admin reach the dashboard", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/admin")

      assert html_response(conn, 200) =~ "Dashboard"
    end
  end
end
