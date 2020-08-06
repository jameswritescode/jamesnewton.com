# frozen_string_literal: true

FactoryBot.define do
  sequence(:title) { |n| "#{n} title" }

  factory :post do
    content { 'content' }
    name { generate(:title) }
  end
end
