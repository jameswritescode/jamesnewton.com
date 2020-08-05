# frozen_string_literal: true

module Mutations
  class UpdateOrCreatePost < Base
    null false

    field :post, Types::PostType, null: false
    field :success, Boolean, null: false

    argument :content, String, required: false
    argument :id, ID, required: false
    argument :name, String, required: false
    argument :state, Types::PostStateType, required: false

    def resolve(id: nil, **kwargs)
      post = Post.find_by(id: id) || Post.new(kwargs)
      success = post.update(kwargs)

      {
        post: post,
        success: success,
      }
    end
  end
end
