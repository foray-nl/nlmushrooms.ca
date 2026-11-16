# frozen_string_literal: true

# Errors only; sampling stays low. Without SENTRY_DSN the SDK is inert.
# PII is kept out by filter_parameter_logging and send_default_pii staying false.
SENTRY_UNSAMPLED_PATHS = %r{\A/(healthcheck|up|assets|cable|rails/active_storage)(/|\z)}

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN', '')
  config.release = ENV.fetch('GIT_REV', '')
  config.environment = ENV.fetch('SENTRY_ENVIRONMENT', Rails.env)
  config.send_default_pii = false
  config.excluded_exceptions += ['SystemExit']
  config.breadcrumbs_logger = %i[active_support_logger http_logger]

  traces_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0.05').to_f
  config.traces_sampler = lambda do |context|
    parent = context[:parent_sampled]
    next parent unless parent.nil?

    path = (context[:rack_env] || {}).fetch('PATH_INFO', '').to_s
    path.match?(SENTRY_UNSAMPLED_PATHS) ? 0.0 : traces_rate
  end
end
