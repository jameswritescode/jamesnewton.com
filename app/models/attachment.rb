# frozen_string_literal: true

class Attachment < ApplicationRecord
  include FileUploader::Attachment(:file)

  validates :file, presence: true

  def embed?
    file.image?
  end
end
