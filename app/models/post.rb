# frozen_string_literal: true

class Post < ApplicationRecord
  validates :content, presence: true
  validates :slug, uniqueness: true
  validates :title, presence: true

  def created
    I18n.l(created_at, format: :short)
  end

  def to_param
    slug
  end

  def url
    url_helpers.posts_path(self)
  end
end
