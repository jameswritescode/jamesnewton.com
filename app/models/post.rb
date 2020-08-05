# frozen_string_literal: true

class Post < ApplicationRecord
  validates :content, presence: true
  validates :name, presence: true
  validates :slug, uniqueness: true, presence: true

  enum state: {
    draft: 0,
    published: 1,
  }

  before_validation :generate_slug

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
      description: content.tr("\n", ' ').truncate(160),
      title: "James Newton | #{name}",
      type: 'article',
      url: controller.posts_url(self),
    }
  end

  private

  def generate_slug
    self.slug = name.parameterize
  end
end
