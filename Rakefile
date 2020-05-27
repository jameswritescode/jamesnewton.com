# frozen_string_literal: true

require 'graphql/rake_task'

require_relative 'config/application'

Rails.application.load_tasks

GraphQL::RakeTask.new(schema_name: 'NewtonSchema')
