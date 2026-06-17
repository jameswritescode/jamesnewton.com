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
      render_component(&Components.delete_button/1, event: "delete_gallery", confirm: "Delete it?")

    assert html =~ ~s(phx-click="delete_gallery")
    assert html =~ ~s(data-confirm="Delete it?")
    refute html =~ "phx-value-id"
  end
end
