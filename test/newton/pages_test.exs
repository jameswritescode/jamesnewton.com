defmodule Newton.PagesTest do
  use Newton.DataCase
  alias Newton.Pages
  alias Newton.Pages.Page

  test "changeset renders body_html from markdown and requires slug/title" do
    cs = Page.changeset(%Page{}, %{slug: "about", title: "About", body_markdown: "## Hi"})
    assert cs.valid?
    assert Ecto.Changeset.get_change(cs, :body_html) =~ "<h2"
  end

  test "changeset coerces a missing body to an empty string" do
    cs = Page.changeset(%Page{}, %{slug: "about", title: "About"})
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :body_markdown) == ""
  end

  test "changeset rejects a reserved slug" do
    cs = Page.changeset(%Page{}, %{slug: "admin", title: "Nope", body_markdown: ""})
    refute cs.valid?
    assert %{slug: [_ | _]} = errors_on(cs)
  end

  test "changeset requires title" do
    cs = Page.changeset(%Page{}, %{slug: "about", body_markdown: ""})
    refute cs.valid?
    assert %{title: [_ | _]} = errors_on(cs)
  end

  describe "context CRUD" do
    @valid %{slug: "about", title: "About", body_markdown: "Hello."}

    test "create_page renders body_html" do
      assert {:ok, page} = Pages.create_page(@valid)
      assert page.body_html =~ "Hello."
    end

    test "create_page enforces slug uniqueness" do
      {:ok, _} = Pages.create_page(@valid)
      assert {:error, cs} = Pages.create_page(@valid)
      assert %{slug: [_ | _]} = errors_on(cs)
    end

    test "get_published_page_by_slug returns published, refuses drafts" do
      {:ok, published} = Pages.create_page(Map.put(@valid, :published, true))

      {:ok, _draft} =
        Pages.create_page(%{slug: "now", title: "Now", body_markdown: "", published: false})

      assert Pages.get_published_page_by_slug("about").id == published.id
      assert Pages.get_published_page_by_slug("now") == nil
      assert Pages.get_page_by_slug("now").slug == "now"
    end

    test "list_sitemap_pages returns only published pages that opted in" do
      {:ok, listed} =
        Pages.create_page(%{slug: "listed", title: "L", published: true, in_sitemap: true})

      {:ok, _} = Pages.create_page(%{slug: "unlisted", title: "U", published: true})
      {:ok, _} = Pages.create_page(%{slug: "draft", title: "D", in_sitemap: true})

      assert Enum.map(Pages.list_sitemap_pages(), & &1.id) == [listed.id]
    end

    test "update_page returns {:error, :stale} on a concurrent edit" do
      {:ok, page} = Pages.create_page(@valid)
      {:ok, _fresh} = Pages.update_page(page, %{title: "Won"})
      assert {:error, :stale} = Pages.update_page(page, %{title: "Lost"})
    end

    test "count_pages and count_drafts" do
      {:ok, _} = Pages.create_page(Map.put(@valid, :published, true))

      {:ok, _} =
        Pages.create_page(%{slug: "now", title: "Now", body_markdown: "", published: false})

      assert Pages.count_pages() == 2
      assert Pages.count_drafts() == 1
    end

    test "delete_page removes the row" do
      {:ok, page} = Pages.create_page(@valid)
      assert {:ok, _} = Pages.delete_page(page)
      assert Pages.get_page_by_slug("about") == nil
    end
  end
end
