defmodule NewtonWeb.HelpersTest do
  use ExUnit.Case, async: true

  alias NewtonWeb.Helpers

  test "format_date/1 formats dates" do
    assert "May 6, 1992" == Helpers.format_date(~D[1992-05-06])
    assert "May 6, 1992" == Helpers.format_date(~U[1992-05-06 12:34:56Z])
  end

  test "format_date/1 returns empty string for nil without on_nil" do
    assert "" == Helpers.format_date(nil)
  end

  test "format_date/2 returns on_nil value for nil" do
    assert "N/A" == Helpers.format_date(nil, on_nil: "N/A")
  end

  test "format_date/2 uses non-nil value when present" do
    assert "May 6, 1992" == Helpers.format_date(~D[1992-05-06], on_nil: "N/A")
    assert "May 6, 1992" == Helpers.format_date(~U[1992-05-06 12:34:56Z], on_nil: "N/A")
  end
end
