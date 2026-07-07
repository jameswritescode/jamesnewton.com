defmodule NewtonWeb.LinksHTML do
  use NewtonWeb, :html

  embed_templates "links_html/*"

  defdelegate external?(url), to: Newton.Links

  @doc """
  The data manifest the Gibson cinematic reads (a JSON island in the page):
  the scene styles these however it wants — the visible page stays free to
  speak the site's own design language. `pixel: true` marks links that leave
  through the mosaic transition.
  """
  def gibson_manifest(links) do
    entries =
      Enum.map(links, fn link ->
        %{
          name: link.name,
          desc: link.description,
          url: link.url,
          external: external?(link.url),
          pixel: false
        }
      end)

    home = %{
      name: "JN.SYS",
      desc: "Disconnect. Return to jamesnewton.com.",
      url: "/",
      external: false,
      pixel: true
    }

    Jason.encode!(entries ++ [home], escape: :html_safe)
  end
end
