# frozen_string_literal: true

module Types
  class MutationType < BaseObject
    field :login, mutation: Mutations::Login
  end
end
