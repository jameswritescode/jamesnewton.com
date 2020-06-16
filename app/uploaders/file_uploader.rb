# frozen_string_literal: true

class FileUploader < Shrine
  plugin :remote_url, max_size: 20_971_520
end
