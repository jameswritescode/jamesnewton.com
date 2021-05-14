# frozen_string_literal: true

class NewtonSchema < GraphQL::Schema
  disable_introspection_entry_points if Rails.env.production?

  use GraphQL::Analysis::AST
  use GraphQL::Execution::Interpreter

  mutation Types::MutationType
  query Types::QueryType

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
