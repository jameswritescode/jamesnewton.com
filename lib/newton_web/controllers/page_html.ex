defmodule NewtonWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use NewtonWeb, :html

  embed_templates "page_html/*"

  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %-d, %Y")
  def format_date(%Date{} = d), do: Calendar.strftime(d, "%B %-d, %Y")

  defdelegate verb(status), to: Newton.Reading
  defdelegate image_url(key), to: Newton.Gallery

  attr :item, :map, required: true

  def home_feed_item(%{item: %{kind: :post}} = assigns) do
    ~H"""
    <.feed_item href={~p"/posts/#{@item.payload.slug}"} date={format_date(@item.payload.published_at)}>
      <h3 class="feed-item-title">{@item.payload.title}</h3>
      <p class="feed-item-excerpt">{@item.payload.excerpt}</p>
    </.feed_item>
    """
  end

  def home_feed_item(%{item: %{kind: :book}} = assigns) do
    ~H"""
    <.feed_item href={~p"/reading##{Newton.Slug.slugify(@item.payload.title)}"} variant="book" date={format_date(@item.date)}>
      <p class="feed-item-book">
        {verb(@item.payload.status)} <cite>{@item.payload.title}</cite> by {@item.payload.author}
      </p>
    </.feed_item>
    """
  end

  def home_feed_item(%{item: %{kind: :photo}} = assigns) do
    assigns = assign(assigns, :first, List.first(assigns.item.payload.photos))

    ~H"""
    <.feed_item
      href={~p"/photos##{@item.payload.slug}"}
      variant="photo"
      date={format_date(@item.date)}
      aria-label={"Photos from #{@item.payload.title}, #{format_date(@item.date)}"}
    >
      <img :if={@first} class="feed-item-photo" src={image_url(@first.image_key)} alt="" />
    </.feed_item>
    """
  end
end
