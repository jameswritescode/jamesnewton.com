# frozen_string_literal: true

class Post < ApplicationRecord
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

  def meta(controller)
    {
      description: content.gsub("\n", ' ').truncate(160),
      title: "James Newton | #{name}",
      type: 'article',
      url: controller.posts_url(self),
    }
  end
end
