defmodule NewtonWeb.PostHTML do
  use NewtonWeb, :html

  embed_templates "post_html/*"

  @doc "Format a post date like \"April 17, 2026\"."
  def format_date(nil), do: ""
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %-d, %Y")
end
