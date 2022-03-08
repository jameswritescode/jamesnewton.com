# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Logout, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: LogoutInput!) {
        logout(input: $input) {
          success
        }
      }
    GQL
  end

  it 'is successful' do
    result = execute_graphql(mutation, context: signed_in_user_context, variables: { input: {} })

    expect(result['data']['logout']['success']).to eq true
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'logout')
  end
end
