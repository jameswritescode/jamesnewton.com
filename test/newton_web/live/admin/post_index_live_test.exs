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

  test "lists posts with a status label and a new-post link", %{conn: conn} do
    post_fixture(%{title: "Published", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Draft", slug: "draft", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    assert has_element?(view, "#posts")
    assert has_element?(view, "a", "New post")
    assert render(view) =~ "Published"
    assert render(view) =~ "Draft"
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
