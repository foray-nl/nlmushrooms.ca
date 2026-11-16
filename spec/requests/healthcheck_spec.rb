# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Healthcheck' do
  it 'answers ok with the database reachable' do
    get '/healthcheck'

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'ok')
  end

  it 'answers on an unknown host so the deploy check never depends on the domain list' do
    host! 'unknown.example.test'
    get '/healthcheck'

    expect(response).to have_http_status(:ok)
  end

  it 'reports 503 when the database is down' do
    allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished)
    get '/healthcheck'

    expect(response).to have_http_status(:service_unavailable)
  end
end
