defmodule NewtonWeb.Admin.MediaLiveTest do
  # async: false + a private media root: the audit scans the volume directory,
  # and the globally shared tmp root accumulates files from other suites
  # (editor uploads), which would make clean-state assertions flaky.
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    previous = Application.fetch_env!(:newton, :media_root)

    private =
      Path.join(System.tmp_dir!(), "newton_media_live_#{System.unique_integer([:positive])}")

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

  test "deleting a stray removes the file and its row", %{conn: conn} do
    path = stored_file("stray-one.png")

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    assert has_element?(view, "#media-stray-stray-one")

    view |> element("#media-stray-stray-one button", "Delete") |> render_click()

    refute has_element?(view, "#media-stray-stray-one")
    refute File.exists?(path)
  end

  test "a forged delete for a referenced file is refused", %{conn: conn} do
    {:ok, _post} =
      Newton.Blog.create_post(%{
        slug: "with-image",
        title: "With Image",
        body_markdown: "![](/media/kept.png)"
      })

    path = stored_file("kept.png")

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    render_click(view, "delete_stray", %{"key" => "kept.png"})

    assert File.exists?(path)
  end

  test "a missing file links to the post that references it", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        slug: "broken-post",
        title: "Broken",
        body_markdown: "![](/media/gone.png)"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/media")
    assert has_element?(view, "#media-missing")

    view
    |> element("#media-missing a", "broken-post")
    |> render_click()

    assert_redirect(view, "/admin/posts/#{post.id}/edit")
  end

  test "clean volume renders both empty states", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/media")

    assert render(view) =~ "No orphaned files"
    assert render(view) =~ "No missing files"
  end
end
