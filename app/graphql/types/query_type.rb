# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    field :posts, [PostType], null: false
    def posts
      Post.all.order(created_at: :desc)
    end
  end
end
