# frozen_string_literal: true

module GraphQLHelpers
  def execute_graphql(query, **kwargs)
    NewtonSchema.execute(
      query,
      { context: { controller: controller } }.merge(kwargs),
    )
  end

  def sign_in(user)
    controller.session[:user_id] = user.id
  end
end

module GraphQLMatchers
  extend RSpec::Matchers::DSL

  module RSpecHelpers
    def failure_message_output(actual, expected)
      <<~TEXT
        expected that:

        #{JSON.pretty_generate(actual)}

        would equal:

        #{JSON.pretty_generate(expected)}
      TEXT
    end

    def graphql_error(input)
      { 'errors' => array_including(hash_including(input)) }
    end
  end

  matcher :have_graphql_response do |field_name, inner_response|
    include RSpecHelpers

    match do |actual|
      values_match?({ 'data' => { field_name => inner_response } }, actual.to_h)
    end

    failure_message do |actual|
      failure_message_output(actual, 'data' => { field_name => inner_response })
    end
  end

  matcher :be_missing_graphql_field do |type, field_name|
    include RSpecHelpers

    match do |actual|
      values_match?(
        graphql_error('message' => "Field '#{field_name}' doesn't exist on type '#{type}'"),
        actual.to_h,
      )
    end

    failure_message do |actual|
      failure_message_output(actual, "Field '#{field_name}' doesn't exist on type '#{type}")
    end
  end

  matcher :be_missing_graphql_argument do |type, field_names|
    include RSpecHelpers

    match do |actual|
      values_match?(
        graphql_error(
          'extensions' => hash_including(
            'problems' => array_including(
              'explanation' => "Field is not defined on #{type}",
              'path' => [field_names],
            ),
          ),
        ),
        actual.to_h,
      )
    end
  end
end

RSpec.configure do |c|
  c.include GraphQLHelpers, type: :controller
  c.include GraphQLMatchers, type: :controller
end
