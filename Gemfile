# frozen_string_literal: true

source 'https://rubygems.org'

ruby '2.7.1'

gem 'bcrypt', '~> 3.1.7'
gem 'bootsnap', '>= 1.4.2', require: false
gem 'graphql', '~> 1.10', '>= 1.10.10'
gem 'image_processing', '~> 1.2'
gem 'pg', '~> 0.18.4'
gem 'puma', '~> 4.1'
gem 'rails', '~> 6.0.3', '>= 6.0.3.1'
gem 'redis', '~> 4.0'
gem 'sass-rails', '>= 6'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'webpacker', '~> 4.0'

group :development, :test do
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
end

group :development do
  gem 'graphiql-rails'
  gem 'listen', '~> 3.2'
  gem 'web-console', '>= 3.3.0'

  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'

  gem 'rubocop'
  gem 'rubocop-performance'
  gem 'rubocop-rails'
  gem 'rubocop-rspec'
  gem 'solargraph'
end

group :development, :test do
  gem 'rspec-rails'
end

group :test do
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  gem 'webdrivers'
end

group :production do
  gem 'aws-sdk-s3', require: false
end
