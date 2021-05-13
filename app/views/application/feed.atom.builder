# frozen_string_literal: true

atom_feed do |feed|
  feed.title("James Newton's Feed")
  feed.updated(@posts.last.published_at)

  @posts.each do |post|
    feed.entry(post) do |entry|
      entry.content(post.content)
      entry.title(post.name)

      entry.author do |author|
        author.name('James Newton')
      end
    end
  end
end
