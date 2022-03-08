# frozen_string_literal: true

class NewtonSchema < GraphQL::Schema
  disable_introspection_entry_points if Rails.env.production?

  mutation Types::MutationType
  query Types::QueryType

  class CustomContext < GraphQL::Query::Context
    def current_user
      @current_user ||= User.find_by(id: self[:session][:user_id])
    end
  end

  context_class CustomContext

  OBJECT_FROM_ID_MAP = {
    'Post' => Post,
  }.freeze

  def self.id_from_object(object, _typedef, _context)
    EncryptionService.new.encrypt("#{object.class.name}:#{object.id}")
  end

  def self.object_from_id(unique_id, _context)
    klass, id = EncryptionService.new.decrypt(unique_id).split(':')

    OBJECT_FROM_ID_MAP[klass].find(id)
  end
end
