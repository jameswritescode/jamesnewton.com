# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Post do
  describe '#set_published_at' do
    it 'sets value of published_at when state changes to published' do
      post = create(:post)

      post.update(state: 'published')

      expect(post.published_at).not_to be_nil
    end
  end
end
