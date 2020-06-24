# frozen_string_literal: true

module Mutations
  class UpdateOrCreatePost < Base
    null false

    field :success, Boolean, null: false

    argument :content, String, required: false
    argument :name, String, required: false
    argument :slug, String, required: false

    def resolve(slug: nil, **kwargs)
      post = Post.find_by(slug: slug) || Post.new(kwargs)

      {
        post: post,
        success: post.update(kwargs),
      }
    end
  end
end
