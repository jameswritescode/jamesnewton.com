# frozen_string_literal: true

FactoryBot.define do
  sequence(:email) { |n| "user#{n}@example.com" }

  factory :user do
    email { generate(:email) }
    password { 'password' }
  end
end
