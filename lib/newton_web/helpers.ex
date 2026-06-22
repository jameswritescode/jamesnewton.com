defmodule NewtonWeb.Helpers do
  @moduledoc "View helpers imported across the web layer."

  @doc "See `Newton.Format.format_date/2`."
  @spec format_date(DateTime.t() | Date.t() | nil, [Newton.Format.date_opt()]) :: String.t()
  defdelegate format_date(date, opts \\ []), to: Newton.Format
end
