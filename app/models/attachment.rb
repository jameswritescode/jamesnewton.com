# frozen_string_literal: true

class Attachment < ApplicationRecord
  include FileUploader::Attachment(:file)
end
