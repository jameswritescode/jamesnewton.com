defmodule NewtonWeb.Admin.PostIndexLiveTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  defp post_fixture(attrs) do
    {:ok, post} =
      Newton.Blog.create_post(Map.merge(%{title: "T", slug: "t", body_markdown: "body"}, attrs))

    post
  end

  test "lists posts with a status label", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draft", slug: "draft", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    assert has_element?(view, "#posts")
    assert render(view) =~ "Published"
    assert render(view) =~ "Draft"
  end

  test "New post creates a draft and opens the editor", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    {:error, {:live_redirect, %{to: path}}} =
      view |> element("button", "New post") |> render_click()

    assert path =~ ~r{^/admin/posts/\d+/edit$}

    [draft] = Newton.Blog.list_posts()
    assert draft.title == "Untitled post"
    assert Newton.Blog.publish_status(draft.published_at) == :draft
  end

  test "untouched untitled drafts are discarded when the list loads", %{conn: conn} do
    untouched = post_fixture(%{title: "Untitled post", slug: "untitled-post", body_markdown: ""})
    real = post_fixture(%{title: "Real Draft", slug: "real-draft", body_markdown: "content"})

    {:ok, _view, html} = live(conn, ~p"/admin/posts")

    assert html =~ "Real Draft"
    refute Enum.any?(Newton.Blog.list_posts(), &(&1.id == untouched.id))
    assert Enum.any?(Newton.Blog.list_posts(), &(&1.id == real.id))
  end

  test "deletes a post from the list", %{conn: conn} do
    post = post_fixture(%{title: "Doomed", slug: "doomed"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")
    assert render(view) =~ "Doomed"

    view |> element("#posts button[phx-value-id='#{post.id}']") |> render_click()

    refute render(view) =~ "Doomed"
    assert_raise Ecto.NoResultsError, fn -> Newton.Blog.get_post!(post.id) end
  end
end
