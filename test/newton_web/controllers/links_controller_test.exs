defmodule NewtonWeb.LinksControllerTest do
  use NewtonWeb.ConnCase

  test "GET /links renders every link's name and url", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    for link <- Newton.Links.all() do
      assert html =~ link.name
      assert html =~ link.url
    end
  end

  test "GET /links opens external links in a new tab, safely", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    externals = Enum.filter(Newton.Links.all(), &Newton.Links.external?(&1.url))
    assert externals != []
    assert html =~ ~s(target="_blank")
    assert html =~ ~s(rel="noopener noreferrer")
  end

  test "GET /links offers a way back to the main site", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)
    assert html =~ "JN.SYS"
  end
end
