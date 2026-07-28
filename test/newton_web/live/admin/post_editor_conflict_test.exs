defmodule NewtonWeb.Admin.PostEditorConflictTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  alias Newton.Blog

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp open_editor(conn, attrs \\ %{}) do
    {:ok, post} =
      Blog.create_post(
        Enum.into(attrs, %{
          "title" => "Conflict post",
          "slug" => "conflict-post",
          "body_markdown" => "original body"
        })
      )

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    {view, post}
  end

  defp write_elsewhere(post, body) do
    {:ok, updated} = Blog.update_post(post, %{"body_markdown" => body})
    updated
  end

  defp type_body(view, post, body) do
    view
    |> form("#post-form")
    |> render_change(%{
      "post" => %{"title" => post.title, "slug" => post.slug, "body_markdown" => body}
    })
  end

  defp autosave(view) do
    send(view.pid, :autosave)
    render(view)
  end

  test "a stale autosave shows the conflict banner and keeps the newer content", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")

    type_body(view, post, "stale edit from computer B")
    autosave(view)

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer A"
  end

  test "Load latest adopts the newer version and clears the conflict", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "stale edit from computer B")
    autosave(view)

    view |> element("#conflict-load-latest") |> render_click()

    refute has_element?(view, "#conflict-banner")
    assert view |> element("#post-form") |> render() =~ "from computer A"

    type_body(view, post, "resumed edit")
    autosave(view)
    assert Blog.get_post!(post.id).body_markdown == "resumed edit"
  end

  test "Keep mine deliberately overwrites and clears the conflict", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "mine wins")
    autosave(view)

    view |> element("#conflict-keep-mine") |> render_click()

    refute has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "mine wins"
  end

  test "typing during a conflict never auto-writes", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "first stale edit")
    autosave(view)
    assert has_element?(view, "#conflict-banner")

    type_body(view, post, "kept typing anyway")
    autosave(view)

    assert Blog.get_post!(post.id).body_markdown == "from computer A"
    assert has_element?(view, "#conflict-banner")

    view |> element("#conflict-keep-mine") |> render_click()
    assert Blog.get_post!(post.id).body_markdown == "kept typing anyway"
  end

  test "publishing from a stale window conflicts instead of crashing", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Publish now") |> render_click()

    assert has_element?(view, "#conflict-banner")
    assert is_nil(Blog.get_post!(post.id).published_at)
  end

  test "recover with a matching version restores the client's typing", %{conn: conn} do
    {view, post} = open_editor(conn)

    render_change(view, "recover", %{
      "post" => %{
        "lock_version" => to_string(Blog.get_post!(post.id).lock_version),
        "title" => post.title,
        "slug" => post.slug,
        "body_markdown" => "typed before reconnect"
      }
    })

    autosave(view)

    assert Blog.get_post!(post.id).body_markdown == "typed before reconnect"
    assert view |> element("#post-form") |> render() =~ "typed before reconnect"
  end

  test "recover with a stale version keeps the latest content and writes nothing", %{
    conn: conn
  } do
    {_view, post} = open_editor(conn)
    stale_version = to_string(Blog.get_post!(post.id).lock_version)
    write_elsewhere(post, "from computer A")

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    render_change(view, "recover", %{
      "post" => %{
        "lock_version" => stale_version,
        "title" => post.title,
        "slug" => post.slug,
        "body_markdown" => "stale client body"
      }
    })

    send(view.pid, :autosave)
    render(view)

    assert Blog.get_post!(post.id).body_markdown == "from computer A"
    refute has_element?(view, "#conflict-banner")
    assert view |> element("#post-form") |> render() =~ "from computer A"
  end

  test "a stale manual save of a published post conflicts and keeps the newer content", %{
    conn: conn
  } do
    published = DateTime.truncate(DateTime.utc_now(), :second)

    {view, post} =
      open_editor(conn, %{"slug" => "published-conflict", "published_at" => published})

    write_elsewhere(post, "from computer A")

    view
    |> form("#post-form")
    |> render_submit(%{
      "post" => %{"title" => post.title, "slug" => post.slug, "body_markdown" => "stale save"}
    })

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer A"
  end

  test "Load latest navigates away instead of crashing when the post was deleted elsewhere", %{
    conn: conn
  } do
    {view, post} = open_editor(conn)

    {:ok, _} = Blog.delete_post(post)

    type_body(view, post, "typing into a deleted post")
    autosave(view)

    assert has_element?(view, "#conflict-banner")

    view |> element("#conflict-load-latest") |> render_click()

    assert_redirect(view, ~p"/admin/posts")
  end

  test "Keep mine navigates away instead of crashing when the post was deleted elsewhere", %{
    conn: conn
  } do
    {view, post} = open_editor(conn)

    {:ok, _} = Blog.delete_post(post)

    type_body(view, post, "typing into a deleted post")
    autosave(view)

    assert has_element?(view, "#conflict-banner")

    view |> element("#conflict-keep-mine") |> render_click()

    assert_redirect(view, ~p"/admin/posts")
  end

  test "Keep mine resyncs the editor when the conflict carries no body", %{conn: conn} do
    published = DateTime.truncate(DateTime.utc_now(), :second)

    {view, post} =
      open_editor(conn, %{"slug" => "keep-mine-resync", "published_at" => published})

    write_elsewhere(post, "the other window's rewrite")

    view |> element("button", "Settings") |> render_click()
    view |> element("#publish-drawer button", "Move to draft") |> render_click()

    assert has_element?(view, "#conflict-banner")

    view |> element("#conflict-keep-mine") |> render_click()

    refute has_element?(view, "#conflict-banner")
    updated = Blog.get_post!(post.id)
    assert updated.body_markdown == "the other window's rewrite"
    assert is_nil(updated.published_at)
    assert view |> element("#post-form") |> render() =~ "the other window&#39;s rewrite"
  end

  test "a second collision during Keep mine re-enters conflict instead of losing the banner", %{
    conn: conn
  } do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "mine wins")
    autosave(view)

    assert has_element?(view, "#conflict-banner")

    handler_id = "second-collision-#{post.id}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:newton, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        if metadata.source == "posts" and metadata.params == [post.id] do
          :telemetry.detach(handler_id)
          send(test_pid, :intercepted)
          Blog.update_post(Blog.get_post!(post.id), %{"body_markdown" => "from computer C"})
        end
      end,
      nil
    )

    view |> element("#conflict-keep-mine") |> render_click()
    assert_receive :intercepted

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer C"
  end

  test "the recovery wiring survives future markup edits", %{conn: conn} do
    # LiveViewTest cannot simulate a client reconnect, so the phx-auto-recover
    # wiring itself is otherwise unreachable by any behavioral test.
    {view, _post} = open_editor(conn)

    assert has_element?(view, "#post-form[phx-auto-recover=recover]")
    assert has_element?(view, "#post-form input[name='post[lock_version]'][type=hidden]")
  end

  test "autosave_now during a conflict never writes and keeps the banner up", %{conn: conn} do
    {view, post} = open_editor(conn)
    write_elsewhere(post, "from computer A")
    type_body(view, post, "stale edit from computer B")
    autosave(view)

    assert has_element?(view, "#conflict-banner")

    view |> element("#post_title") |> render_blur()

    assert has_element?(view, "#conflict-banner")
    assert Blog.get_post!(post.id).body_markdown == "from computer A"
  end
end
