defmodule NewtonWeb.Admin.PostEditorStandardTest do
  use NewtonWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    config = Application.get_env(:newton, Newton.Standard)
    Application.put_env(:newton, Newton.Standard, Keyword.put(config, :enabled, true))
    on_exit(fn -> Application.put_env(:newton, Newton.Standard, config) end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  test "publishing a post puts its standard.site record", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Standard post",
        slug: "standard-post",
        body_markdown: "Hello."
      })

    test_pid = self()

    Req.Test.stub(Newton.Standard, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:xrpc, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{"accessJwt" => "tok"})
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    render_click(view, "publish_now", %{})

    assert_receive {:xrpc, "/xrpc/com.atproto.repo.putRecord", %{"rkey" => "standard-post"}},
                   2_000
  end
end
