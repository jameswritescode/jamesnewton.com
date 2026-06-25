defmodule NewtonWeb.LinksHTML do
  use NewtonWeb, :html

  embed_templates "links_html/*"

  defdelegate external?(url), to: Newton.Links
end
