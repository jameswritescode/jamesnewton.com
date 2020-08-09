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

  let(:context) { { current_user: build(:user), controller: OpenStruct.new(session: { user_id: 1 }) } }

  it 'is successful' do
    result = execute_graphql(mutation, context: context, variables: { input: {} })

    aggregate_failures do
      expect(context[:controller].session[:user_id]).to be_nil
      expect(result['data']['logout']['success']).to eq true
    end
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'logout')
  end
end
