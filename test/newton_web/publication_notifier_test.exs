defmodule NewtonWeb.PublicationNotifierTest do
  use ExUnit.Case, async: true
  use NewtonWeb, :verified_routes

  alias Newton.Blog.Post
  alias Newton.Pages.Page
  alias NewtonWeb.PublicationNotifier

  @published %Post{slug: "hello", published_at: ~U[2026-07-01 12:00:00Z]}
  @draft %Post{slug: "hello", published_at: nil}

  @listed_page %Page{slug: "about", published: true, in_sitemap: true}
  @unlisted_page %Page{slug: "about", published: true, in_sitemap: false}
  @draft_page %Page{slug: "about", published: false, in_sitemap: true}

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

  test "draft and opted-out page mutations change nothing" do
    assert PublicationNotifier.changed_page_urls(@draft_page, @draft_page) == []
    assert PublicationNotifier.changed_page_urls(nil, @draft_page) == []
    assert PublicationNotifier.changed_page_urls(@draft_page, nil) == []
    assert PublicationNotifier.changed_page_urls(@unlisted_page, @unlisted_page) == []
    assert PublicationNotifier.changed_page_urls(@draft_page, @unlisted_page) == []
    assert PublicationNotifier.changed_page_urls(@unlisted_page, nil) == []
  end

  test "publishing an opted-in page submits only its URL" do
    assert PublicationNotifier.changed_page_urls(@draft_page, @listed_page) == [url(~p"/about")]
    assert PublicationNotifier.changed_page_urls(nil, @listed_page) == [url(~p"/about")]
  end

  test "editing an opted-in page submits its URL once" do
    assert PublicationNotifier.changed_page_urls(@listed_page, @listed_page) == [url(~p"/about")]
  end

  test "renaming an opted-in page submits the old and new URLs" do
    renamed = %Page{@listed_page | slug: "colophon"}

    assert PublicationNotifier.changed_page_urls(@listed_page, renamed) ==
             [url(~p"/about"), url(~p"/colophon")]
  end

  test "toggling the sitemap opt-in submits the URL either way" do
    assert PublicationNotifier.changed_page_urls(@unlisted_page, @listed_page) == [
             url(~p"/about")
           ]

    assert PublicationNotifier.changed_page_urls(@listed_page, @unlisted_page) == [
             url(~p"/about")
           ]
  end

  test "unpublishing and deleting an opted-in page submit the dead URL" do
    assert PublicationNotifier.changed_page_urls(@listed_page, @draft_page) == [url(~p"/about")]
    assert PublicationNotifier.changed_page_urls(@listed_page, nil) == [url(~p"/about")]
  end
end
