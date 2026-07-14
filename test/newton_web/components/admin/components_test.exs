defmodule NewtonWeb.Admin.ComponentsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  alias NewtonWeb.Admin.Components

  test "drawer_footer renders the slot primary, a Cancel link, and Delete when deletable" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Components.drawer_footer
        cancel_path="/admin/reading"
        deletable?={true}
        delete_event="delete"
        delete_id={7}
        delete_confirm="Delete this entry?"
      >
        PRIMARY-SLOT
      </Components.drawer_footer>
      """)

    assert html =~ "PRIMARY-SLOT"
    assert html =~ "Cancel"
    assert html =~ "Delete"
    assert html =~ ~s(data-confirm="Delete this entry?")
    assert html =~ ~s(phx-value-id="7")
  end

  test "drawer_footer omits Delete and Cancel when not configured" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Components.drawer_footer deletable?={false}>
        PRIMARY-SLOT
      </Components.drawer_footer>
      """)

    assert html =~ "PRIMARY-SLOT"
    refute html =~ "Delete"
    refute html =~ "Cancel"
  end

  test "save_button renders a submit labeled Save" do
    html = render_component(&Components.save_button/1, %{})
    assert html =~ ~s(type="submit")
    assert html =~ "Save"
  end

  test "delete_button omits phx-value-id when no id is given" do
    html =
      render_component(&Components.delete_button/1,
        event: "delete_gallery",
        confirm: "Delete it?"
      )

    assert html =~ ~s(phx-click="delete_gallery")
    assert html =~ ~s(data-confirm="Delete it?")
    refute html =~ "phx-value-id"
  end

  defp h(template), do: rendered_to_string(template)

  test "page_header renders the title and right-aligned actions" do
    assigns = %{}

    html =
      h(~H"""
      <Components.page_header title="Posts">
        <button>New post</button>
      </Components.page_header>
      """)

    assert html =~ "Posts"
    assert html =~ "New post"
  end

  test "page_header works without actions" do
    assigns = %{}
    assert h(~H|<Components.page_header title="Dashboard" />|) =~ "Dashboard"
  end

  test "section_header renders an h2 with the title" do
    assigns = %{}
    html = h(~H|<Components.section_header title="Images" />|)
    assert html =~ "<h2"
    assert html =~ "Images"
  end

  test "list renders a stream container with a wired empty state" do
    assigns = %{}

    html =
      h(~H"""
      <Components.list id="things" empty="No things yet.">
        <div id="thing-1">one</div>
      </Components.list>
      """)

    assert html =~ ~s(id="things")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="things-empty")
    assert html =~ "No things yet."
    assert html =~ "one"
  end

  test "list_item renders each meta entry in a non-wrapping cell" do
    assigns = %{}

    html =
      h(~H"""
      <Components.list_item id="row-3" navigate="/x">
        Title
        <:meta><span>September 17, 2025</span></:meta>
      </Components.list_item>
      """)

    assert html =~ "whitespace-nowrap"
    assert html =~ "contents"
    refute html =~ "shrink-0"
  end

  test "list_item links via navigate or patch and places all slots" do
    assigns = %{}

    navigate =
      h(~H"""
      <Components.list_item id="row-1" navigate="/admin/posts/1/edit">
        Title text
        <:leading><span>thumb</span></:leading>
        <:inline><span>author</span></:inline>
        <:meta><span>badge</span></:meta>
        <:meta><span>date</span></:meta>
      </Components.list_item>
      """)

    assert navigate =~ ~s(href="/admin/posts/1/edit")
    assert navigate =~ ~s(data-phx-link="redirect")
    assert navigate =~ "Title text"

    for piece <- ~w(thumb author badge date) do
      assert navigate =~ piece
    end

    patch =
      h(~H"""
      <Components.list_item id="row-2" patch="/admin/reading/2/edit">
        Entry
      </Components.list_item>
      """)

    assert patch =~ ~s(data-phx-link="patch")
  end
end
