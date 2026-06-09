defmodule Newton.Feed do
  @moduledoc """
  Merged home-feed stream across posts, reading entries, and photo groups.
  Each item is normalized to `%{date: Date.t(), kind: atom, payload: struct}`
  and sorted newest-first.
  """
  alias Newton.{Blog, Gallery, Reading}

  def recent(limit \\ 10) do
    # Each source fetches at most `limit` rows — you never need more than that
    # from one type to fill the global top N — so the DB work stays bounded.
    (post_items(limit) ++ reading_items(limit) ++ photo_items(limit))
    |> Enum.sort_by(& &1.date, {:desc, Date})
    |> Enum.take(limit)
  end

  defp post_items(limit) do
    for p <- Blog.list_published_posts(limit) do
      %{date: DateTime.to_date(p.published_at), kind: :post, payload: p}
    end
  end

  defp reading_items(limit) do
    for e <- Reading.recent_finished(limit) do
      %{date: e.finished_at, kind: :book, payload: e}
    end
  end

  defp photo_items(limit) do
    for g <- Gallery.recent_groups(limit) do
      %{date: g.taken_on, kind: :photo, payload: g}
    end
  end
end
