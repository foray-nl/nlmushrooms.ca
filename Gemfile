# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.12'

# Community Engine, pinned to a reviewed commit on github/main (never branch: 'main').
# 1c26c4678 contains the trusted domains, seed packet, storage routing and installer fixes
# listed in docs/runbooks/ce-static-site-migration-dedicated-host.md section 2.
gem 'better_together', '~> 0.11.0',
    github: 'better-together-org/community-engine-rails',
    ref: '1c26c4678de17d95936efea0fed424c7e69d99e1'

# Forks the engine needs; they are not on rubygems.
gem 'pundit-resources', '~> 1.1.4', github: 'better-together-org/pundit-resources'
gem 'storext', github: 'better-together-org/storext'

gem 'rails', '~> 8.1.4'

gem 'aws-sdk-s3', require: false
gem 'bcrypt', '~> 3.1.22'
gem 'bootsnap', '>= 1.7.0', require: false
gem 'connection_pool', '~> 3.0.2'
gem 'importmap-rails'
gem 'ostruct'
gem 'pg', '>= 0.18', '< 2.0'
gem 'puma', '~> 8.0'
gem 'rack-protection'
gem 'redis', '~> 6.0'
gem 'sidekiq', '~> 8.1.1'
gem 'stimulus-rails'
gem 'turbo-rails'
gem 'tzinfo-data', platforms: %i[windows jruby]

# Error reporting (Sentry protocol; Bugsink compatible). No-op without SENTRY_DSN.
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'sentry-sidekiq'

# Audit and lint tools sit in this group, which CI installs; the production image skips it.
group :development, :test do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'factory_bot_rails'
  gem 'i18n-tasks', '~> 1.1.2'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-factory_bot', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-rspec_rails', require: false
end

group :development do
  gem 'web-console'
end

group :test do
  gem 'capybara'
end
