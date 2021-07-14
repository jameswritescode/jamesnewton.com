# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NewtonSchema do
  it 'matches the dumped schema (rails graphql:schema:dump)', :aggregate_failures do
    context = { GRAPHQL_RAKE_TASK: true }

    expect(described_class.to_definition(context: context)).to eq(File.read(Rails.root.join('schema.graphql')))
    expect(described_class.to_json(context: context)).to eq(File.read(Rails.root.join('schema.json')).rstrip)
  end
end
