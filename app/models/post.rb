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
  before_validation :set_published_at, if: :state_changed?

  scope :published_desc, -> { published.order(published_at: :desc) }

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
      title: "#{name} | James Newton",
      type: 'article',
      url: controller.posts_url(self),
    }
  end

  private

  def set_published_at
    self.published_at = DateTime.current if state == 'published'
  end

  def generate_slug
    self.slug = name.parameterize
  end
end
