# frozen_string_literal: true

module Types
  class MutationType < BaseObject
    field :login, mutation: Mutations::Login
    field :update_or_create_post, mutation: Mutations::UpdateOrCreatePost, user_only: true
  end
end
