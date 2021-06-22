# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    field :attachments, [AttachmentType, { null: true }], null: false, user_only: true
    def attachments
      Attachment.all.order(created_at: :desc)
    end

    field :latest_tweet, TweetType, null: false
    def latest_tweet
      TwitterService.new
    end

    field :me, UserType, null: true
    def me
      context[:controller]&.current_user
    end

    field :post, PostType, null: true do
      argument :slug, String, required: true
    end
    def post(slug:)
      Post.find_by(slug: slug)
    end

    field :posts, [PostType, { null: true }], null: false do
      argument :limit, Integer, required: false
    end
    def posts(limit: nil)
      query = Post.all
      query = query.limit(limit) if limit.present?
      query
    end
  end
end
