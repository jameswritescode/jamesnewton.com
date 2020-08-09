# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Login, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: LoginInput!) {
        login(input: $input) {
          success
        }
      }
    GQL
  end

  let(:context) { { controller: OpenStruct.new(session: {}) } }

  it 'is successful' do
    user = create(:user)

    result = execute_graphql(
      mutation,
      context: context,
      variables: { input: { email: user.email, password: 'password' } },
    )

    aggregate_failures do
      expect(context[:controller].session[:user_id]).to eq user.id
      expect(result['data']['login']['success']).to eq true
    end
  end

  it 'fails' do
    result = execute_graphql(
      mutation,
      context: context,
      variables: { input: { email: 'whatever', password: 'whatever' } },
    )

    expect(result['data']['login']['success']).to eq false
  end
end
