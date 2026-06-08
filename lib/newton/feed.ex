defmodule Newton.Feed do
  @moduledoc """
  Merged home-feed stream across posts, reading entries, and photo groups.
  Each item is normalized to `%{date: Date.t(), kind: atom, payload: struct}`
  and sorted newest-first.
  """
  alias Newton.{Blog, Reading, Gallery}

  def recent(limit \\ 10) do
    (post_items() ++ reading_items() ++ photo_items())
    |> Enum.sort_by(& &1.date, {:desc, Date})
    |> Enum.take(limit)
  end

  defp post_items do
    for p <- Blog.list_published_posts() do
      %{date: DateTime.to_date(p.published_at), kind: :post, payload: p}
    end
  end

  defp reading_items do
    for e <- Reading.list_entries(), not is_nil(e.finished_at) do
      %{date: e.finished_at, kind: :book, payload: e}
    end
  end

  defp photo_items do
    for g <- Gallery.list_groups(), not is_nil(g.taken_on) do
      %{date: g.taken_on, kind: :photo, payload: g}
    end
  end
end
