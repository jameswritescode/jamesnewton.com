defmodule NewtonWeb.Admin.PostEditorIndexNowTest do
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    config = Application.get_env(:newton, Newton.IndexNow)
    Application.put_env(:newton, Newton.IndexNow, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, Newton.IndexNow, config) end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  test "publishing a post submits its URL to IndexNow", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "IndexNow post",
        slug: "indexnow-post",
        body_markdown: "Hello."
      })

    test_pid = self()

    Req.Test.stub(Newton.IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:indexnow_request, Jason.decode!(body)})
      Req.Test.json(conn, %{})
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    render_click(view, "publish_now", %{})

    assert_receive {:indexnow_request, %{"urlList" => urls}}, 2_000
    assert url(~p"/posts/indexnow-post") in urls
    assert url(~p"/posts") in urls
  end
end
