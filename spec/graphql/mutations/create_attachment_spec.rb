# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CreateAttachment, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: CreateAttachmentInput!) {
        createAttachment(input: $input)
      }
    GQL
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'createAttachment')
  end
end
