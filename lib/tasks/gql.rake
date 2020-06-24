# frozen_string_literal: true

task gql: :environment do
  Rake::Task['graphql:schema:dump'].invoke
  sh('yarn graphql-codegen')
end
