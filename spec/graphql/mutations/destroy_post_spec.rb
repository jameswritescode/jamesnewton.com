# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::DestroyPost, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: DestroyPostInput!) {
        destroyPost(input: $input) {
          success
        }
      }
    GQL
  end

  it 'is not visible to signed out users' do
    expect(execute_graphql(mutation)).to be_missing_graphql_field('Mutation', 'destroyPost')
  end

  it 'destroys post' do
    post = create(:post)

    result = execute_graphql(
      mutation,
      context: signed_in_user_context,
      variables: { input: { slug: post.slug } },
    )

    aggregate_failures do
      expect(Post.exists?(post.id)).to eq false
      expect(result['data']['destroyPost']['success']).to eq true
    end
  end
end
