# frozen_string_literal: true

# Optional host allow-list. Platform domains are managed in the database, so leave APP_HOSTS
# unset unless the hostnames are fixed; the engine resolves the platform from the Host header
# and refuses unknown hosts itself. Health paths must never be blocked by host authorization.
Rails.application.config.hosts.concat(ENV.fetch('APP_HOSTS', '').split(',').map(&:strip).compact_blank)
Rails.application.config.host_authorization = {
  exclude: ->(request) { %w[/up /healthcheck].include?(request.path) }
}
