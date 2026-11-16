# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.year.to_i}" }

  if (asset_host = ENV['ASSET_HOST'].presence)
    config.asset_host = asset_host
  end

  # local (default) or s3_compatible for Garage; see config/storage.yml.
  config.active_storage.service = ENV.fetch('ACTIVE_STORAGE_SERVICE', 'local').to_sym

  # TLS ends at the proxy chain. Default to secure; the health paths are never redirected.
  config.assume_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch('ASSUME_SSL', 'true'))
  config.force_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', 'true'))
  config.ssl_options = { redirect: { exclude: ->(request) { %w[/up /healthcheck].include?(request.path) } } }

  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')
  config.silence_healthcheck_path = '/healthcheck'
  config.active_support.report_deprecations = false

  # Redis cache with a connection pool, namespaced per app.
  cache_pool = ConnectionPool.new(size: ENV.fetch('REDIS_CACHE_POOL_SIZE', 5).to_i,
                                  timeout: ENV.fetch('REDIS_CACHE_POOL_TIMEOUT', 5).to_f) do
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
  end
  config.cache_store = :redis_cache_store, { redis: cache_pool, pool: false, namespace: 'cache_nlmushrooms_ce' }

  # No queue prefix: Redis is dedicated to this app, and the engine's scheduled jobs name bare queues.
  config.active_job.queue_adapter = :sidekiq

  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: ENV.fetch('MAILER_HOST', 'ce.nlmushrooms.ca'), protocol: 'https' }
  if ENV['SMTP_ADDRESS'].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV.fetch('SMTP_ADDRESS'), port: ENV.fetch('SMTP_PORT', 587).to_i,
      user_name: ENV.fetch('SMTP_USERNAME', nil), password: ENV.fetch('SMTP_PASSWORD', nil),
      authentication: :plain, enable_starttls_auto: true
    }
  end

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [:id]
end
