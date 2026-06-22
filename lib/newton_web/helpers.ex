defmodule NewtonWeb.Helpers do
  @type format_date_opt :: {:on_nil, String.t()}

  @spec format_date(DateTime.t() | Date.t() | nil, [format_date_opt()]) :: String.t()
  def format_date(date, opts \\ [])

  def format_date(%DateTime{} = dt, _opts), do: Calendar.strftime(dt, "%B %-d, %Y")
  def format_date(%Date{} = d, _opts), do: Calendar.strftime(d, "%B %-d, %Y")
  def format_date(nil, opts), do: Keyword.get(opts, :on_nil, "")
end
