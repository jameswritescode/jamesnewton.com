# frozen_string_literal: true

class NewtonSchema < GraphQL::Schema
  use GraphQL::Analysis::AST
  use GraphQL::Execution::Interpreter

  mutation Types::MutationType
  query Types::QueryType
end
