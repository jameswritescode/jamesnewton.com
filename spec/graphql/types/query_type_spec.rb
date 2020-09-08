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
      sign_in(user)

      expect(execute_graphql(query)).not_to be_missing_graphql_field('Query', 'attachments')
    end
  end

  describe '#me' do
    let(:query) do
      <<~GQL
        query {
          me {
            id
          }
        }
      GQL
    end

    it 'returns data for signed in user' do
      user = create(:user)

      sign_in(user)

      expect(execute_graphql(query)).to match(
        'data' => {
          'me' => {
            'id' => user.id.to_s,
          },
        },
      )
    end

    it 'returns null for visitors' do
      expect(execute_graphql(query)).to match(
        'data' => {
          'me' => nil,
        },
      )
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
      sign_in(user)

      expect(execute_graphql(query)).to match(
        'data' => {
          'posts' => [
            { 'state' => 'draft' },
            { 'state' => 'published' },
          ],
        },
      )
    end

    it 'does not show drafts to users' do
      expect(execute_graphql(query)).to match(
        'data' => {
          'posts' => [
            { 'state' => 'published' },
          ],
        },
      )
    end
  end
end
