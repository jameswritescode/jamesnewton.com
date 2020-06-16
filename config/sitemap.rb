# frozen_string_literal: true

SitemapGenerator::Sitemap.default_host = 'https://jamesnewton.com'
SitemapGenerator::Sitemap.public_path = 'tmp/'
SitemapGenerator::Sitemap.sitemaps_host = 'https://jamesnewton-development.s3-us-west-2.amazonaws.com/sitemaps/'
SitemapGenerator::Sitemap.sitemaps_path = 'sitemaps/'

credentials = Rails.application.credentials[Rails.env.to_sym]

SitemapGenerator::Sitemap.adapter = SitemapGenerator::AwsSdkAdapter.new(
  credentials.dig(:aws, :bucket),
  aws_access_key_id: credentials.dig(:aws, :access_key_id),
  aws_region: credentials.dig(:aws, :region),
  aws_secret_access_key: credentials.dig(:aws, :secret_access_key),
)

SitemapGenerator::Sitemap.create do
  Post.find_each do |post|
    add posts_path(post), lastmod: post.updated_at
  end
end
