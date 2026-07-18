defmodule Newton.Analytics.HourlyView do
  @moduledoc "One UTC hour's view count for one public path."
  use Ecto.Schema

  schema "hourly_views" do
    field :hour, :utc_datetime
    field :path, :string
    field :count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
