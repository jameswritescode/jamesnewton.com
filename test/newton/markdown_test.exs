defmodule Newton.MarkdownTest do
  use ExUnit.Case, async: true
  alias Newton.Markdown

  test "to_html renders GFM tables" do
    md = "| A | B |\n|---|---|\n| 1 | 2 |"
    html = Markdown.to_html(md)
    assert html =~ "<table>"
    assert html =~ "<td>1</td>"
  end

  test "to_html highlights fenced code with language class output" do
    md = "```elixir\ndefmodule Foo do\nend\n```"
    html = Markdown.to_html(md)
    assert html =~ "<pre"
    assert html =~ "defmodule"
  end

  test "to_html escapes raw HTML by default (unsafe disabled)" do
    html = Markdown.to_html("<script>alert(1)</script>")
    refute html =~ "<script>"
  end

  test "excerpt takes the first paragraph as plain text, truncated" do
    md = "First paragraph with **bold** text that goes on.\n\nSecond paragraph."
    excerpt = Markdown.excerpt(md)
    assert excerpt =~ "First paragraph with bold text"
    refute excerpt =~ "**"
    refute excerpt =~ "Second paragraph"
  end

  test "excerpt truncates very long first paragraphs with an ellipsis" do
    long = String.duplicate("word ", 80)
    excerpt = Markdown.excerpt(long)
    assert String.length(excerpt) <= 205
    assert String.ends_with?(excerpt, "…")
  end

  test "reading_time returns whole minutes, minimum 1" do
    assert Markdown.reading_time("just a few words") == 1
    assert Markdown.reading_time(String.duplicate("word ", 400)) == 2
  end
end
