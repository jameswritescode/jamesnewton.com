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
    file = ApolloUploadServer::Wrappers::UploadedFile.new(fixture_file_upload('kitten.jpg'))

    response = execute_graphql(
      mutation,
      context: signed_in_user_context,
      variables: { input: { file: file } },
    )

    expect(response['data']['createAttachment']['success']).to eq true
  end
end
