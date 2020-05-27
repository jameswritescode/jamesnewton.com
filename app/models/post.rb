# frozen_string_literal: true

class Post < ApplicationRecord
  validates :content, presence: true
  validates :slug, uniqueness: true
  validates :title, presence: true
end
