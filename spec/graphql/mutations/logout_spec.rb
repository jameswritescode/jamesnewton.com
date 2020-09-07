# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GraphqlController, type: :controller do
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
    sign_in(create(:user))

    result = execute_graphql(mutation, variables: { input: {} })

    aggregate_failures do
      expect(controller.session[:user_id]).to be_nil
      expect(result['data']['logout']['success']).to eq true
    end
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'logout')
  end
end
