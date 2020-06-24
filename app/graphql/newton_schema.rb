# frozen_string_literal: true

class NewtonSchema < GraphQL::Schema
  disable_introspection_entry_points if Rails.env.production?

  use GraphQL::Analysis::AST
  use GraphQL::Execution::Interpreter

  mutation Types::MutationType
  query Types::QueryType
end
