defmodule NewtonWeb.Helpers do
  @moduledoc "View helpers imported across the web layer."

  defdelegate format_date(date, opts \\ []), to: Newton.Format
  defdelegate format_reading_time(minutes), to: Newton.Format
end
