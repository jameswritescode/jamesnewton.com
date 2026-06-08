defmodule NewtonWeb.ReadingHTML do
  use NewtonWeb, :html

  embed_templates "reading_html/*"

  def format_date(nil), do: ""
  def format_date(%Date{} = d), do: Calendar.strftime(d, "%B %-d, %Y")

  defdelegate verb(status), to: Newton.Reading
end
