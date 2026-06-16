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

  test "New post opens the editor without creating a row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/posts")

    {:error, {:live_redirect, %{to: path}}} =
      view |> element("a", "New post") |> render_click()

    assert path == ~p"/admin/posts/new"
    assert Newton.Blog.list_posts() == []
  end

  test "the drafts filter shows only drafts", %{conn: conn} do
    post_fixture(%{title: "Live Article", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Work In Progress", slug: "draftee", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts?filter=drafts")

    assert has_element?(view, "#posts", "Work In Progress")
    refute has_element?(view, "#posts", "Live Article")
  end

  test "the published filter shows only published", %{conn: conn} do
    post_fixture(%{title: "Live Article", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Work In Progress", slug: "draftee", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts?filter=published")

    assert has_element?(view, "#posts", "Live Article")
    refute has_element?(view, "#posts", "Work In Progress")
  end

  test "switching filters re-streams the list", %{conn: conn} do
    post_fixture(%{title: "Live Article", slug: "pub", published_at: ~U[2026-01-01 00:00:00Z]})
    post_fixture(%{title: "Work In Progress", slug: "draftee", published_at: nil})

    {:ok, view, _html} = live(conn, ~p"/admin/posts")
    view |> element(~s(a[href="/admin/posts?filter=drafts"])) |> render_click()

    assert has_element?(view, "#posts", "Work In Progress")
    refute has_element?(view, "#posts", "Live Article")
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
