# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = 'https://jamesnewton.com'
SitemapGenerator::Sitemap.public_path = 'tmp/'
SitemapGenerator::Sitemap.sitemaps_path = 'sitemaps/'

credentials = Rails.application.credentials[Rails.env.to_sym][:aws]
bucket = credentials[:bucket]

SitemapGenerator::Sitemap.sitemaps_host = "https://#{bucket}.s3-us-west-2.amazonaws.com/"

SitemapGenerator::Sitemap.adapter = SitemapGenerator::AwsSdkAdapter.new(
  bucket,
  **credentials.transform_keys { |key| "aws_#{key}" }.symbolize_keys,
)

SitemapGenerator::Sitemap.create do
  add resume_path

  Post.find_each do |post|
    add posts_path(post), lastmod: post.updated_at
  end
end
