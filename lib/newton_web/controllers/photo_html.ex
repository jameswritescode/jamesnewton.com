defmodule NewtonWeb.PhotoHTML do
  use NewtonWeb, :html

  embed_templates "photo_html/*"

  def format_month(nil), do: ""
  def format_month(%Date{} = d), do: Calendar.strftime(d, "%B %Y")

  defdelegate image_url(key), to: Newton.Gallery
end
