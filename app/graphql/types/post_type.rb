# frozen_string_literal: true

module Types
  class PostType < Types::BaseObject
    field :id, ID, null: false
    field :created, String, null: false
    field :name, String, null: false
    field :url, String, null: false
  end
end
