# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CreateAttachment, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: CreateAttachmentInput!) {
        createAttachment(input: $input) {
          success
          url
        }
      }
    GQL
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'createAttachment')
  end

  it 'works for signed in users' do
    sign_in(create(:user))

    file = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/kitten.jpg'), 'image/jpg')

    response = execute_graphql(
      mutation,
      variables: { input: { file: file } },
    )

    expect(response['data']['createAttachment']['success']).to eq true
  end
end
