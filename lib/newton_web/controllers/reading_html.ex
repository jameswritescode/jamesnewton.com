defmodule NewtonWeb.ReadingHTML do
  use NewtonWeb, :html

  embed_templates "reading_html/*"

  defdelegate verb(status), to: Newton.Reading
end
