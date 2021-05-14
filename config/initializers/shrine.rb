# frozen_string_literal: true

if Rails.env.test?
  require 'shrine/storage/memory'

  storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::Memory.new,
  }
else
  require 'shrine/storage/s3'

  aws = Rails.application.credentials[Rails.env.to_sym][:aws]

  storages = {
    cache: Shrine::Storage::S3.new(prefix: 'uploads/cache', **aws),
    store: Shrine::Storage::S3.new(prefix: 'uploads', public: true, **aws),
  }
end

Shrine.storages = storages

Shrine.plugin :activerecord
Shrine.plugin :cached_attachment_data
Shrine.plugin :determine_mime_type
Shrine.plugin :model
Shrine.plugin :restore_cached_data
Shrine.plugin :type_predicates
