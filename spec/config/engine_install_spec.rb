# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Community Engine install' do
  it 'runs the engine migrations from the gem, not from copies' do
    expect(BetterTogether.host_migrations_mode).to eq(:gem)
    expect(Rails.root.glob('db/migrate/*.better_together.rb')).to be_empty
  end

  it 'mounts the engine' do
    expect(Rails.application.routes.routes.map { |r| r.app.app }).to include(BetterTogether::Engine)
  end

  it 'uses the postgis adapter' do
    expect(ActiveRecord::Base.connection.adapter_name.downcase).to include('postgis')
  end

  it 'defines the s3_compatible storage service without secrets in the file' do
    storage = Rails.root.join('config/storage.yml').read

    expect(storage).to include('s3_compatible:')
    expect(storage).not_to match(%r{secret_access_key:\s*[A-Za-z0-9+/]{20,}})
  end

  it 'passes the migration-copy guard script' do
    expect(system(Rails.root.join('bin/check-engine-migrations').to_s, out: File::NULL)).to be(true)
  end
end
