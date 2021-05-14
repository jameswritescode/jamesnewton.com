# frozen_string_literal: true

class Attachment < ApplicationRecord
  include FileUploader::Attachment(:file)

  belongs_to :post, optional: true

  validates :file, presence: true

  def embed?
    file.image?
  end
end
