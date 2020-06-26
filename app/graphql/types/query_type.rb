# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    field :attachments, [AttachmentType, null: true], null: false, user_only: true
    def attachments
      Attachment.all.order(created_at: :desc)
    end

    field :latest_tweet, TweetType, null: false
    def latest_tweet
      TwitterService.new
    end

    field :me, UserType, null: true
    def me
      context[:current_user]
    end

    field :post, PostType, null: true do
      argument :slug, String, required: true
    end
    def post(slug:)
      Post.find_by(slug: slug)
    end

    field :posts, [PostType, null: true], null: false
    def posts
      Post.all.order(created_at: :desc)
    end
  end
end
