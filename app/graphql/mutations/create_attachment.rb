# frozen_string_literal: true

module Mutations
  class CreateAttachment < Base
    null false

    field :success, Boolean, null: false
    field :url, String, null: true

    argument :file, ApolloUploadServer::Upload, required: true

    def resolve(file:)
      attachment = Attachment.new(file: file)
      success = attachment.save

      {
        success: success,
        url: attachment.file_url,
      }
    end
  end
end
