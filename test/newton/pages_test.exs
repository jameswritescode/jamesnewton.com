defmodule Newton.PagesTest do
  use Newton.DataCase
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
end
