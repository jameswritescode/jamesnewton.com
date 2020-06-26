# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::QueryType, type: :graphql do
  describe '#attachments' do
    let(:query) do
      <<~GQL
        query {
          attachments
        }
      GQL
    end

    it 'is not visible to signed out users' do
      expect(execute_graphql(query)).to be_missing_graphql_field('Query', 'attachments')
    end

    it 'is visible to signed in users' do
      result = execute_graphql(query, context: { current_user: create(:user) })

      expect(result).not_to be_missing_graphql_field('Query', 'attachments')
    end
  end
end
