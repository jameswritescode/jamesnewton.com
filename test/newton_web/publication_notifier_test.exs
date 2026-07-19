defmodule NewtonWeb.PublicationNotifierTest do
  use ExUnit.Case, async: true
  use NewtonWeb, :verified_routes

  alias Newton.Blog.Post
  alias NewtonWeb.PublicationNotifier

  @published %Post{slug: "hello", published_at: ~U[2026-07-01 12:00:00Z]}
  @draft %Post{slug: "hello", published_at: nil}

  test "draft-only mutations change nothing" do
    assert PublicationNotifier.changed_urls(@draft, @draft) == []
    assert PublicationNotifier.changed_urls(nil, @draft) == []
    assert PublicationNotifier.changed_urls(@draft, nil) == []
    assert PublicationNotifier.changed_urls(nil, nil) == []
  end

  test "publishing submits the post URL and the feed pages" do
    assert PublicationNotifier.changed_urls(@draft, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert PublicationNotifier.changed_urls(nil, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "editing a published post submits its URL once" do
    assert PublicationNotifier.changed_urls(@published, @published) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "a slug change submits the old and new URLs" do
    renamed = %Post{@published | slug: "renamed"}

    assert PublicationNotifier.changed_urls(@published, renamed) ==
             [url(~p"/posts/hello"), url(~p"/posts/renamed"), url(~p"/"), url(~p"/posts")]
  end

  test "unpublishing and deleting submit the dead URL" do
    assert PublicationNotifier.changed_urls(@published, @draft) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]

    assert PublicationNotifier.changed_urls(@published, nil) ==
             [url(~p"/posts/hello"), url(~p"/"), url(~p"/posts")]
  end

  test "draft-only mutations produce no standard operations" do
    assert PublicationNotifier.standard_ops(@draft, @draft) == []
    assert PublicationNotifier.standard_ops(nil, @draft) == []
    assert PublicationNotifier.standard_ops(@draft, nil) == []
    assert PublicationNotifier.standard_ops(nil, nil) == []
  end

  test "publishing puts the document" do
    assert PublicationNotifier.standard_ops(@draft, @published) == [{:put_document, @published}]
    assert PublicationNotifier.standard_ops(nil, @published) == [{:put_document, @published}]
  end

  test "editing a published post re-puts the document" do
    assert PublicationNotifier.standard_ops(@published, @published) ==
             [{:put_document, @published}]
  end

  test "a slug change deletes the old record and puts the new one" do
    renamed = %Post{@published | slug: "renamed"}

    assert PublicationNotifier.standard_ops(@published, renamed) ==
             [{:delete_document, "hello"}, {:put_document, renamed}]
  end

  test "unpublishing and deleting remove the record" do
    assert PublicationNotifier.standard_ops(@published, @draft) == [{:delete_document, "hello"}]
    assert PublicationNotifier.standard_ops(@published, nil) == [{:delete_document, "hello"}]
  end
end
