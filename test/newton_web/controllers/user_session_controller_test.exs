defmodule NewtonWeb.UserSessionControllerTest do
  use NewtonWeb.ConnCase, async: true

  import Newton.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /login - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_newton_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/admin"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/login?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  describe "passkey endpoints" do
    test "challenge returns a base64url challenge and stores it in the session", %{conn: conn} do
      conn = get(conn, ~p"/login/passkey/challenge")
      assert %{"challenge" => challenge, "rpId" => _} = json_response(conn, 200)
      assert is_binary(challenge)
      assert get_session(conn, :passkey_challenge)
    end

    test "login rejects an unknown credential", %{conn: conn} do
      conn = get(conn, ~p"/login/passkey/challenge")

      conn =
        post(conn, ~p"/login/passkey", %{
          "id" => Base.url_encode64(<<0, 0, 0>>, padding: false),
          "authenticatorData" => "AA",
          "clientDataJSON" => "AA",
          "signature" => "AA"
        })

      assert json_response(conn, 401)
      refute get_session(conn, :user_token)
    end

    test "login rejects when there is no challenge in the session", %{conn: conn} do
      conn =
        post(conn, ~p"/login/passkey", %{
          "id" => Base.url_encode64(<<0, 0, 0>>, padding: false),
          "authenticatorData" => "AA",
          "clientDataJSON" => "AA",
          "signature" => "AA"
        })

      assert json_response(conn, 401)
    end
  end
end
