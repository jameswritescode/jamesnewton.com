# frozen_string_literal: true

unless Rails.env.test?
  require 'shrine/storage/s3'

  credentials = Rails.application.credentials[Rails.env.to_sym]

  s3_options = {
    access_key_id: credentials.dig(:aws, :access_key_id),
    bucket: credentials.dig(:aws, :bucket),
    region: 'us-west-2',
    secret_access_key: credentials.dig(:aws, :secret_access_key),
  }

  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: 'uploads/cache', **s3_options),
    store: Shrine::Storage::S3.new(prefix: 'uploads', public: true, **s3_options),
  }

  Shrine.plugin :activerecord
  Shrine.plugin :cached_attachment_data
  Shrine.plugin :determine_mime_type
  Shrine.plugin :model
  Shrine.plugin :restore_cached_data
end
