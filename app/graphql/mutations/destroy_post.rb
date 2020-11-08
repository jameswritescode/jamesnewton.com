# frozen_string_literal: true

module Mutations
  class DestroyPost < Base
    field :success, Boolean, null: false

    argument :slug, String, required: true

    def resolve(slug:)
      { success: Post.find_by(slug: slug).destroy }
    end
  end
end
