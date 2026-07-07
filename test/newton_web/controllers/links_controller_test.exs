defmodule NewtonWeb.LinksControllerTest do
  use NewtonWeb.ConnCase

  # The server-rendered page is the plain fallback (site design language) plus
  # the #gibson-links JSON island the Gibson cinematic reads. Most visitors see
  # the WebGL tower; the page serves no-JS/no-WebGL visitors, crawlers, and
  # ?fallback.

  test "GET /links renders every link's name, url, and description", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    for link <- Newton.Links.all() do
      assert html =~ link.name
      assert html =~ link.url
      assert html =~ link.description
    end
  end

  test "GET /links carries the JSON manifest the cinematic reads", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    assert [_, json] =
             Regex.run(
               ~r{<script type="application/json" id="gibson-links">\s*(.*?)\s*</script>}s,
               html
             )

    entries = Jason.decode!(json)
    first = Newton.Links.all() |> List.first()

    assert Enum.any?(
             entries,
             &(&1["name"] == first.name and &1["url"] == first.url and
                 &1["desc"] == first.description)
           )

    assert List.last(entries)["name"] == "JN.SYS"
    assert List.last(entries)["pixel"] == true
  end

  test "GET /links opens external links in a new tab, safely", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    externals = Enum.filter(Newton.Links.all(), &Newton.Links.external?(&1.url))
    assert externals != []
    assert html =~ ~s(target="_blank")
    assert html =~ ~s(rel="noopener noreferrer")
  end
end
