# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    attr_reader :user_only

    argument_class Types::BaseArgument

    def initialize(*args, user_only: false, **kwargs, &block)
      @user_only = user_only

      super(*args, **kwargs, &block)
    end

    def visible?(context)
      return true if context[:GRAPHQL_RAKE_TASK]

      super && (!user_only || context.current_user.present?)
    end
  end
end
