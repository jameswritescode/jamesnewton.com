# frozen_string_literal: true

module Types
  class PostStateType < Types::BaseEnum
    Post.states.keys.each do |key|
      value key
    end
  end
end
