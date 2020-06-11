# frozen_string_literal: true

module Types
  class MutationType < BaseObject
    field :test, Boolean, null: false
    def test
      true
    end
  end
end
