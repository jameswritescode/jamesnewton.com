# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    field :post, PostType, null: true do
      argument :slug, String, required: true
    end
    def post(slug:)
      Post.find_by(slug: slug)
    end

    field :posts, [PostType], null: false
    def posts
      Post.all.order(created_at: :desc)
    end

    field :latest_tweet, TweetType, null: false
    def latest_tweet
      TwitterService.new
    end
  end
end
