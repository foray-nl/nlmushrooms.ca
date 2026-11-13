# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative '../scripts/apply_layout'

RSpec.describe 'Past Forays directory (layout/forays.yml)' do
  let(:root) { ApplyLayout::ROOT }
  let(:forays) { ApplyLayout.forays }
  let(:directory) { File.read(File.join(root, 'past_forays.html')) }

  it 'lists forays newest first' do
    years = directory.scan(/id="foray-(\d{4})"/).flatten.map(&:to_i)
    expect(years).to eq(years.sort.reverse)
    expect(years).to eq(forays.map { |f| f['year'] })
  end

  it 'has unique years and existing foray pages and card images' do
    expect(forays.map { |f| f['year'] }.uniq.size).to eq(forays.size)
    forays.each do |f|
      expect(File.exist?(File.join(root, f['page']))).to be(true), "#{f['page']} missing" if f['page']
      expect(File.exist?(File.join(root, 'images', 'forays', "#{f['year']}.jpg"))).to be(true), "card image #{f['year']}" if f['art']
    end
  end

  it 'redirects the old foray_reports URLs to past_forays.html' do
    toml = File.read(File.join(root, 'netlify.toml'))
    %w[/foray_reports.html /foray_reports].each do |from|
      expect(toml).to match(%r{from = "#{from}"\n\s*to = "/past_forays.html"\n\s*status = 301})
    end
  end

  it 'emits Event JSON-LD on every foray page that has dates' do
    forays.select { |f| f['page'] && f['start'] }.each do |f|
      html = File.read(File.join(root, f['page']))
      graph = JSON.parse(html[%r{<script type="application/ld\+json">\n(.*?)\n\s*</script>}m, 1])['@graph']
      event = graph.find { |n| n['@type'] == 'Event' }
      expect(event).not_to be_nil, "#{f['page']} has no Event"
      expect(event['startDate']).to eq(f['start'].to_s)
      expect(event['endDate']).to eq(f['end'].to_s)
      expect(event['organizer']).to eq('@id' => "#{ApplyLayout.site['url']}/#organization")
    end
  end
end
