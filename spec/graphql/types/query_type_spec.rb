# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::QueryType, type: :graphql do
  let(:user) { create(:user) }

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
      result = execute_graphql(query, context: { current_user: user })

      expect(result).not_to be_missing_graphql_field('Query', 'attachments')
    end
  end

  describe '#posts' do
    let(:query) do
      <<~GQL
        query {
          posts {
            state
          }
        }
      GQL
    end

    before do
      create(:post, state: 'published')
      create(:post)
    end

    it 'shows drafts to users' do
      expect(execute_graphql(query, context: { current_user: user }).to_h).to match(
        'data' => {
          'posts' => [
            { 'state' => 'draft' },
            { 'state' => 'published' },
          ],
        },
      )
    end

    it 'does not show drafts to users' do
      expect(execute_graphql(query).to_h).to match(
        'data' => {
          'posts' => [
            { 'state' => 'published' },
          ],
        },
      )
    end
  end
end
