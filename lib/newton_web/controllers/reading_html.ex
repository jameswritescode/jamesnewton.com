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

  attr :name, :string, required: true
  attr :entries, :list, required: true

  def series_group(assigns) do
    assigns = assign(assigns, :author, shared_author(assigns.entries))

    ~H"""
    <section class="feed-series" aria-labelledby={"series-#{Newton.Slug.slugify(@name)}"}>
      <h2 id={"series-#{Newton.Slug.slugify(@name)}"} class="feed-series-label">
        {@name}<span :if={@author}> · {@author}</span>
      </h2>
      <.book_item :for={entry <- @entries} entry={entry} show_author={is_nil(@author)} />
    </section>
    """
  end

  defp shared_author([first | rest]) do
    if Enum.all?(rest, &(&1.author == first.author)), do: first.author
  end
end
