# frozen_string_literal: true

module Types
  class MutationType < BaseObject
    field :login, mutation: Mutations::Login
    field :logout, mutation: Mutations::Logout, user_only: true

    field :create_attachment, mutation: Mutations::CreateAttachment, user_only: true
    field :update_or_create_post, mutation: Mutations::UpdateOrCreatePost, user_only: true
  end
end
