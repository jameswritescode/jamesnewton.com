# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NewtonSchema do
  it 'matches the dumped schema (rails graphql:schema:dump)' do
    context = { GRAPHQL_RAKE_TASK: true }

    aggregate_failures do
      expect(described_class.to_definition(context: context)).to eq(File.read(Rails.root.join('schema.graphql')).rstrip)
      expect(described_class.to_json(context: context)).to eq(File.read(Rails.root.join('schema.json')).rstrip)
    end
  end
end
