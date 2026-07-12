defmodule NewtonWeb.Admin.DashboardDriftTest do
  # async: false + a private media root: the audit scans the volume directory,
  # and the globally shared tmp root accumulates files from other suites
  # (editor uploads), which would make clean-state assertions flaky.
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    previous = Application.fetch_env!(:newton, :media_root)

    private =
      Path.join(System.tmp_dir!(), "newton_dashboard_drift_#{System.unique_integer([:positive])}")

    File.mkdir_p!(private)
    Application.put_env(:newton, :media_root, private)

    on_exit(fn ->
      Application.put_env(:newton, :media_root, previous)
      File.rm_rf!(private)
    end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)

  defp stored_file(key) do
    File.mkdir_p!(media_root())
    path = Path.join(media_root(), key)
    File.write!(path, "img-bytes")
    path
  end

  test "shows a media drift notice when the volume disagrees with the ledger", %{conn: conn} do
    stored_file("dash-stray.png")

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#media-drift")

    view |> element("#media-drift") |> render_click()
    assert_redirect(view, "/admin/media")
  end

  test "no drift notice when volume and ledger agree", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")
    refute has_element?(view, "#media-drift")
  end
end
