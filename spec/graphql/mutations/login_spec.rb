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

  it 'is successful' do
    user = create(:user)

    result = execute_graphql(
      mutation,
      variables: { input: { email: user.email, password: 'password' } },
    )

    expect(result['data']['login']['success']).to eq true
  end

  it 'fails' do
    result = execute_graphql(
      mutation,
      variables: { input: { email: 'whatever', password: 'whatever' } },
    )

    expect(result['data']['login']['success']).to eq false
  end
end
