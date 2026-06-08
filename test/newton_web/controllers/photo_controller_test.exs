defmodule NewtonWeb.PhotoControllerTest do
  use NewtonWeb.ConnCase
  alias Newton.Gallery

  test "GET /photos renders groups and photos", %{conn: conn} do
    {:ok, g} =
      Gallery.create_group(%{
        slug: "eastern-sierra",
        title: "Eastern Sierra",
        caption: "Granite and water.",
        taken_on: ~D[2025-06-01]
      })

    {:ok, _} =
      Gallery.add_photo(g, %{
        image_key: "https://example.com/a.jpg",
        alt: "Morning light",
        position: 1
      })

    html = conn |> get(~p"/photos") |> html_response(200)
    assert html =~ "Eastern Sierra"
    assert html =~ "Granite and water."
    assert html =~ ~s(id="eastern-sierra")
    assert html =~ "https://example.com/a.jpg"
    assert html =~ ~s(alt="Morning light")
  end
end
