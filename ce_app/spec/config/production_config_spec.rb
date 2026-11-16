# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Production configuration files' do
  let(:procfile) { Rails.root.join('Procfile').read }
  let(:app_json) { JSON.parse(Rails.root.join('app.json').read) }

  it 'runs migrations in the release phase and never seeds on deploy' do
    expect(procfile).to match(/^release: bundle exec rails db:migrate$/)
    expect(app_json.fetch('scripts', {})).not_to have_key('postdeploy')
  end

  it 'checks the healthcheck path after deploy' do
    check = app_json.dig('healthchecks', 'web', 0)

    expect(check).to include('path' => '/healthcheck')
  end

  it 'keeps the libxml2 CVE stage in the production Dockerfile' do
    dockerfile = Rails.root.join('Dockerfile').read

    expect(dockerfile).to include('libxml2-2.15.4.tar.xz').and include('sha256sum -c')
  end

  it 'processes every queue the engine enqueues on' do
    queues = YAML.safe_load(ERB.new(Rails.root.join('config/sidekiq.yml').read).result, aliases: true)
    production = queues.dig('production', 'queues').map(&:first)

    expect(production).to include('default', 'mailers', 'notifications', 'maintenance', 'metrics', 'weather')
  end

  it 'ignores key files and env files' do
    ignore = Rails.root.join('.gitignore').read

    expect(ignore).to include('/config/master.key').and include('/config/credentials/*.key').and include('/.env*')
  end
end
