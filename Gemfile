# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.1.2'

gem 'rails', '~> 7.0'

gem 'apollo_upload_server', '~> 2.0', '>= 2.0.5'
gem 'awesome_print'
gem 'aws-sdk-s3'
gem 'bcrypt', '~> 3.1.7'
gem 'bootsnap', '>= 1.4.2', require: false
gem 'graphql', '~> 1.10', '>= 1.10.10'
gem 'image_processing', '~> 1.2'
gem 'jsbundling-rails', '~> 1.0.2'
gem 'matrix'
gem 'mini_mime', '~> 1.0', '>= 1.0.2'
gem 'oauth', '~> 0.5.5'
gem 'pg', '~> 1.2.3'
gem 'puma', '~> 4.3'
gem 'redis', '~> 4.0'
gem 'rollbar'
gem 'sass-rails', '>= 6'
gem 'shrine', '~> 3.3'
gem 'sitemap_generator', '~> 6.1', '>= 6.1.2'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

group :development, :test do
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
end

group :development do
  gem 'graphql-rails_logger'

  gem 'listen', '~> 3.5.1'
  gem 'web-console', '>= 3.3.0'

  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'

  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'solargraph', require: false
end

group :development, :test do
  gem 'factory_bot_rails'
  gem 'rspec-rails'
end

group :test do
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  gem 'webdrivers'
end

group :production do
  gem 'barnes', '~> 0.0.8'
end
