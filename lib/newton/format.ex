defmodule Newton.Format do
  @moduledoc "Shared, layer-neutral formatting helpers used by both the domain and web layers."

  @type date_opt :: {:on_nil, String.t()}

  @doc ~S"""
  Formats a date as `"April 17, 2026"`. `nil` yields the `:on_nil` string
  (default `""`).
  """
  @spec format_date(DateTime.t() | Date.t() | nil, [date_opt()]) :: String.t()
  def format_date(date, opts \\ [])
  def format_date(%DateTime{} = dt, _opts), do: Calendar.strftime(dt, "%B %-d, %Y")
  def format_date(%Date{} = d, _opts), do: Calendar.strftime(d, "%B %-d, %Y")
  def format_date(nil, opts), do: Keyword.get(opts, :on_nil, "")

  @spec format_reading_time(integer()) :: String.t()
  def format_reading_time(minutes) do
    "#{minutes} minute read"
  end
end
