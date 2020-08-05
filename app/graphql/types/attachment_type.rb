# frozen_string_literal: true

module Types
  class AttachmentType < BaseObject
    implements NodeType

    field :embed, Boolean, method: :embed?, null: false
    field :url, String, method: :file_url, null: false

    field :extension, String, null: false
    def extension
      object.file.extension
    end

    field :filename, String, null: false
    def filename
      object.file.metadata['filename']
    end
  end
end
