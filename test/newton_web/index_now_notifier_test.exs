defmodule NewtonWeb.IndexNowNotifierTest do
  use ExUnit.Case, async: true
  use NewtonWeb, :verified_routes

  alias Newton.Blog.Post
  alias NewtonWeb.IndexNowNotifier

  @published %Post{slug: "hello", published_at: ~U[2026-07-01 12:00:00Z]}
  @draft %Post{slug: "hello", published_at: nil}

  test "draft-only mutations change nothing" do
    assert IndexNowNotifier.changed_urls(@draft, @draft) == []
    assert IndexNowNotifier.changed_urls(nil, @draft) == []
    assert IndexNowNotifier.changed_urls(@draft, nil) == []
    assert IndexNowNotifier.changed_urls(nil, nil) == []
  end

  test "publishing submits the post URL and the feed pages" do
    assert IndexNowNotifier.changed_urls(@draft, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert IndexNowNotifier.changed_urls(nil, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "editing a published post submits its URL once" do
    assert IndexNowNotifier.changed_urls(@published, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "a slug change submits the old and new URLs" do
    renamed = %Post{@published | slug: "renamed"}

    assert IndexNowNotifier.changed_urls(@published, renamed) ==
             [url(~p"/posts/hello"), url(~p"/posts/renamed"), url(~p"/"), url(~p"/posts")]
  end

  test "unpublishing and deleting submit the dead URL" do
    assert IndexNowNotifier.changed_urls(@published, @draft) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert IndexNowNotifier.changed_urls(@published, nil) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end
end
