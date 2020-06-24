# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::UpdateOrCreatePost, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateOrCreatePostInput!) {
        updateOrCreatePost(input: $input) {
          success
        }
      }
    GQL
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'updateOrCreatePost')
  end

  it 'is visible to signed in users' do
    result = execute_graphql(mutation, context: { current_user: create(:user) })

    expect(result).not_to be_missing_graphql_field('Mutation', 'updateOrCreatePost')
  end
end