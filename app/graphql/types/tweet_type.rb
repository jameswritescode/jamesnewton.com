# frozen_string_literal: true

module Types
  class TweetType < BaseObject
    field :content, String, null: false
    field :created, String, null: false
  end
end
