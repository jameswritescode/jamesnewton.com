defmodule NewtonWeb.ReadingHTML do
  use NewtonWeb, :html

  embed_templates "reading_html/*"

  defdelegate verb(status), to: Newton.Reading

  attr :entry, Newton.Reading.Entry, required: true
  attr :show_author, :boolean, default: true

  def book_item(assigns) do
    ~H"""
    <.feed_item
      id={Newton.Slug.slugify(@entry.title)}
      variant="book"
      date={format_date(@entry.finished_at)}
    >
      <p class="feed-item-book">
        {verb(@entry.status)}
        <cite>{@entry.title}</cite><span :if={@show_author}> by {@entry.author}</span>
      </p>

      <p :if={@entry.note} class="feed-item-book-caption">{@entry.note}</p>
    </.feed_item>
    """
  end

  @doc "The single author shared by every entry in a series group, or nil."
  def shared_author([first | rest]) do
    if Enum.all?(rest, &(&1.author == first.author)), do: first.author
  end
end
