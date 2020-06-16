# frozen_string_literal: true

class Post < ApplicationRecord
  has_many_attached :attachments

  validates :content, presence: true
  validates :name, presence: true
  validates :slug, uniqueness: true

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
