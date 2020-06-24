# frozen_string_literal: true

require 'graphql/rake_task'

require_relative 'config/application'

Rails.application.load_tasks

GraphQL::RakeTask.new(
  load_context: ->(_task) { { GRAPHQL_RAKE_TASK: true } },
  schema_name: 'NewtonSchema',
)
