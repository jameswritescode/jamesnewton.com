# frozen_string_literal: true

class NewtonSchema < GraphQL::Schema
  mutation Types::MutationType
  query Types::QueryType

  use GraphQL::Execution::Interpreter
  use GraphQL::Analysis::AST
end
