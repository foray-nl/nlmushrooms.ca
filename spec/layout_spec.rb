# frozen_string_literal: true

require_relative '../scripts/apply_layout'

RSpec.describe ApplyLayout do
  it 'has every page that carries layout markers in sync with layout/partials' do
    drifted = described_class.pages.select do |file|
      source = File.read(file, encoding: 'UTF-8')
      source.include?('<!-- layout:') && described_class.render(source, file) != source
    end.map { |f| f.sub("#{described_class::ROOT}/", '') }

    expect(drifted).to be_empty, "run `ruby scripts/apply_layout.rb`; out of date: #{drifted.join(', ')}"
  end

  it 'has a partial for every region' do
    described_class::REGIONS.each do |name|
      expect(File).to exist(File.join(described_class::PARTIALS, "#{name}.html"))
    end
  end

  describe '.render' do
    let(:page) do
      "<body>\n  <!-- layout:nav -->\n  stale\n  <!-- /layout:nav -->\n  <p>kept</p>\n</body>\n"
    end

    it 'replaces only the marked region and keeps its indentation' do
      out = described_class.render(page, 'foray_2026.html')
      expect(out).to include("  <nav aria-label=\"Main navigation\">\n")
      expect(out).not_to include('stale')
      expect(out).to include("  <p>kept</p>\n")
    end

    it 'marks only the link to the page being written as active' do
      out = described_class.render(page, 'foray_2026.html')
      expect(out.scan('class="active"').size).to eq(1)
      expect(out).to include('<a href="foray_2026.html" class="active">')
    end

    it 'marks nothing active on a page that is not in the nav' do
      expect(described_class.render(page, 'foray_2025.html')).not_to include('class="active"')
    end

    it 'is idempotent' do
      once = described_class.render(page, 'foray_2026.html')
      expect(described_class.render(once, 'foray_2026.html')).to eq(once)
    end
  end
end
