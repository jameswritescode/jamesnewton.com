# frozen_string_literal: true

module Mutations
  class Login < Base
    null false

    field :success, Boolean, null: false

    argument :email, String, required: true
    argument :password, String, required: true

    def resolve(email:, password:)
      user = User.find_by(email: email)
      user = user&.authenticate(password)
      context[:session][:user_id] = user.id if user.present?

      { success: user.present? }
    end
  end
end
