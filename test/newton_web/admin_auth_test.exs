defmodule NewtonWeb.AdminAuthTest do
  use NewtonWeb.ConnCase, async: true

  describe "registration is disabled" do
    test "GET /users/register returns 404", %{conn: conn} do
      conn = get(conn, "/users/register")
      assert conn.status == 404
    end
  end
end
