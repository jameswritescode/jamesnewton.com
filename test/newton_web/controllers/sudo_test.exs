defmodule NewtonWeb.SudoTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  defp make_stale(conn) do
    offset_user_token(get_session(conn, :user_token), -11, :minute)
    conn
  end

  describe "sudo gate on /admin/settings" do
    test "a fresh session reaches settings directly", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:ok, _view, _html} = live(conn, ~p"/admin/settings")
    end

    test "a stale session is bounced to the confirm page", %{conn: conn} do
      conn = log_in_user(conn, user_fixture()) |> make_stale()

      assert {:error, {:redirect, %{to: "/login/confirm-access", flash: flash}}} =
               live(conn, ~p"/admin/settings")

      assert flash["error"] =~ "Confirm it's you"
    end

    test "an unauthenticated visitor is bounced to login, not the confirm page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/settings")
    end
  end

  describe "session hygiene on elevation" do
    setup %{conn: conn} do
      user = user_fixture() |> set_password()
      %{conn: log_in_user(conn, user) |> make_stale(), user: user}
    end

    defp session_token_count(user) do
      import Ecto.Query

      Newton.Repo.aggregate(
        from(t in Newton.Accounts.UserToken,
          where: t.user_id == ^user.id and t.context == "session"
        ),
        :count
      )
    end

    test "elevating rotates the session, discarding anything held in it", %{conn: conn} do
      conn = conn |> put_session(:stale_marker, "value") |> put_session(:user_return_to, "/x")

      conn =
        post(conn, ~p"/login/confirm-access", %{"user" => %{"password" => valid_user_password()}})

      assert redirected_to(conn) == ~p"/admin/settings"
      refute get_session(conn, :stale_marker)
      refute get_session(conn, :user_return_to)
      assert get_session(conn, :user_token)
    end

    test "elevating replaces the old token instead of leaving it valid", %{
      conn: conn,
      user: user
    } do
      before_token = get_session(conn, :user_token)
      assert session_token_count(user) == 1

      conn =
        post(conn, ~p"/login/confirm-access", %{"user" => %{"password" => valid_user_password()}})

      after_token = get_session(conn, :user_token)
      assert after_token != before_token
      assert session_token_count(user) == 1
      refute Newton.Accounts.get_user_by_session_token(before_token)
    end

    test "a failed password attempt leaves the session untouched", %{conn: conn, user: user} do
      before_token = get_session(conn, :user_token)

      conn = post(conn, ~p"/login/confirm-access", %{"user" => %{"password" => "wrong"}})

      assert get_session(conn, :user_token) == before_token
      assert session_token_count(user) == 1
    end

    test "a failed passkey attempt burns the challenge", %{conn: conn} do
      conn = get(conn, ~p"/login/passkey/challenge")
      assert get_session(conn, :passkey_challenge)

      conn =
        post(conn, ~p"/login/confirm-access/passkey", %{
          "id" => "bogus",
          "authenticatorData" => "bogus",
          "clientDataJSON" => "bogus",
          "signature" => "bogus"
        })

      assert json_response(conn, 401)
      refute get_session(conn, :passkey_challenge)
    end
  end

  describe "password re-authentication" do
    setup %{conn: conn} do
      user = user_fixture() |> set_password()
      %{conn: log_in_user(conn, user) |> make_stale(), user: user}
    end

    test "the correct password reopens sudo and returns to settings", %{conn: conn} do
      conn =
        post(conn, ~p"/login/confirm-access", %{"user" => %{"password" => valid_user_password()}})

      assert redirected_to(conn) == ~p"/admin/settings"

      # The rotated token makes the follow-up request sudo-fresh.
      assert {:ok, _view, _html} = live(conn, ~p"/admin/settings")
    end

    test "a wrong password stays gated with an error", %{conn: conn} do
      conn =
        post(conn, ~p"/login/confirm-access", %{"user" => %{"password" => "not the password"}})

      assert redirected_to(conn) == ~p"/login/confirm-access"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "didn't match"

      # Still stale — settings remains gated.
      assert {:error, {:redirect, %{to: "/login/confirm-access"}}} =
               live(conn, ~p"/admin/settings")
    end

    test "the confirm page renders both methods", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login/confirm-access")

      assert has_element?(view, "#sudo_form")
      assert has_element?(view, "#sudo-passkey-button")
    end
  end

  describe "passkey re-authentication" do
    @bogus_assertion %{
      "id" => Base.url_encode64(<<0, 0, 0>>, padding: false),
      "authenticatorData" => "AA",
      "clientDataJSON" => "AA",
      "signature" => "AA"
    }

    test "rejects an unknown credential", %{conn: conn} do
      conn =
        log_in_user(conn, user_fixture())
        |> make_stale()
        |> get(~p"/login/passkey/challenge")

      conn = post(conn, ~p"/login/confirm-access/passkey", @bogus_assertion)
      assert json_response(conn, 401)
    end

    test "rejects when there is no challenge in the session", %{conn: conn} do
      conn = log_in_user(conn, user_fixture()) |> make_stale()

      conn = post(conn, ~p"/login/confirm-access/passkey", @bogus_assertion)
      assert json_response(conn, 401)
    end
  end
end
