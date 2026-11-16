# frozen_string_literal: true

# Dokku and the load balancer probe this path. It is unauthenticated, locale-free and
# touches the database so a broken connection fails the deploy check.
class HealthcheckController < ActionController::API
  def index
    ActiveRecord::Base.connection.execute('SELECT 1')
    render json: { status: 'ok' }
  rescue ActiveRecord::ActiveRecordError
    render json: { status: 'database unavailable' }, status: :service_unavailable
  end
end
