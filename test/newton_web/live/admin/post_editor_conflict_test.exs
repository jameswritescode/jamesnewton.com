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
end
