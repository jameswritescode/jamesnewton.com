# frozen_string_literal: true

source 'https://rubygems.org'

gem 'rails', '~> 8.1.1'

gem 'bcrypt', '~> 3.1.7'
gem 'image_processing', '~> 1.2'
gem 'jbuilder'
gem 'propshaft'
gem 'puma', '>= 5.0'
gem 'sqlite3', '>= 2.1'
gem 'tzinfo-data', platforms: %i[windows jruby]

gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

gem 'bootsnap', require: false
gem 'kamal', require: false
gem 'thruster', require: false

gem 'inertia_rails', '~> 3.15'
gem 'js-routes', '~> 2.3'
gem 'vite_rails', '~> 3.0'

group :development, :test do
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'

  gem 'brakeman', require: false
  gem 'bundler-audit', require: false

  gem 'rubocop-capybara', require: false
  gem 'rubocop-i18n', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
end

group :development do
  gem 'web-console'
end

group :test do
  gem 'capybara'
  gem 'capybara-lockstep'

  gem 'selenium-webdriver'
end
