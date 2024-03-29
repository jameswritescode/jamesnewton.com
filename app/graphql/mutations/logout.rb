# frozen_string_literal: true

module Mutations
  class Logout < Base
    field :success, Boolean, null: false

    def resolve
      context[:session][:user_id] = nil

      { success: true }
    end
  end
end
