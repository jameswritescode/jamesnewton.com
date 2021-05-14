# frozen_string_literal: true

module Mutations
  class CreateAttachment < Base
    null false

    field :success, Boolean, null: false
    field :url, String, null: true

    argument :file, ApolloUploadServer::Upload, required: true
    argument :post_id, ID, required: false, loads: Types::PostType

    def resolve(file:, post: nil)
      attachment = Attachment.new(file: file, post: post)
      success = attachment.save

      {
        success: success,
        url: attachment.file_url,
      }
    end
  end
end
