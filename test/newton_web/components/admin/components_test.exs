defmodule NewtonWeb.Admin.ComponentsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias NewtonWeb.Admin.Components

  test "drawer_footer renders Cancel and Save, and Delete when deletable" do
    html =
      render_component(&Components.drawer_footer/1,
        cancel_path: "/admin/reading",
        deletable?: true,
        delete_event: "delete",
        delete_id: 7,
        delete_confirm: "Delete this entry?"
      )

    assert html =~ "Cancel"
    assert html =~ "Save"
    assert html =~ "Delete"
    assert html =~ ~s(data-confirm="Delete this entry?")
    assert html =~ ~s(phx-value-id="7")
  end

  test "drawer_footer omits Delete when not deletable" do
    html =
      render_component(&Components.drawer_footer/1, cancel_path: "/admin/reading", deletable?: false)

    assert html =~ "Save"
    assert html =~ "Cancel"
    refute html =~ "Delete"
  end

  test "delete_button omits phx-value-id when no id is given" do
    html =
      render_component(&Components.delete_button/1, event: "delete_gallery", confirm: "Delete it?")

    assert html =~ ~s(phx-click="delete_gallery")
    assert html =~ ~s(data-confirm="Delete it?")
    refute html =~ "phx-value-id"
  end
end
