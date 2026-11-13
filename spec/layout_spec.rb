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
      expect(out).to include("  <nav class=\"navbar navbar-expand-lg navbar-dark\" aria-label=\"Main navigation\">\n")
      expect(out).not_to include('stale')
      expect(out).to include("  <p>kept</p>\n")
    end

    it 'marks only the link to the page being written as active' do
      out = described_class.render(page, 'foray_2026.html')
      expect(out.scan('nav-link active').size).to eq(1)
      expect(out).to include('<a class="nav-link active" aria-current="page" href="foray_2026.html">')
    end

    it 'marks a dropdown item and its parent toggle active on a sub-page' do
      out = described_class.render(page, 'species_lists.html')
      expect(out).to include('<a class="dropdown-item active" aria-current="page" href="species_lists.html">')
      expect(out.scan('dropdown-toggle active').size).to eq(1)
      expect(out).to match(/dropdown-toggle active"[^>]*>Species List</)
    end

    it 'marks nothing active on a page that is not in the nav' do
      expect(described_class.render(page, 'foray_2025.html')).not_to include('nav-link active')
    end

    it 'is idempotent' do
      once = described_class.render(page, 'foray_2026.html')
      expect(described_class.render(once, 'foray_2026.html')).to eq(once)
    end

  describe 'breadcrumb and section menu (layout/site-nav.yml)' do
    let(:page) do
      "<main>\n  <!-- layout:breadcrumb -->\n  x\n  <!-- /layout:breadcrumb -->\n  <!-- layout:section-nav -->\n  x\n  <!-- /layout:section-nav -->\n</main>\n"
    end

    it 'builds Home > Section > Page on a sub-page, with the last crumb as plain text' do
      out = described_class.render(page, 'mission.html')
      expect(out).to include('<li class="breadcrumb-item"><a href="index.html">Home</a></li>')
      expect(out).to include('<li class="breadcrumb-item"><a href="about_us.html">About Us</a></li>')
      expect(out).to include('<li class="breadcrumb-item active" aria-current="page">Mission</li>')
    end

    it 'stops at the section overview on the section page itself' do
      out = described_class.render(page, 'about_us.html')
      expect(out).to include('<li class="breadcrumb-item active" aria-current="page">About Us</li>')
      expect(out).not_to include('mission.html</a></li>')
    end

    it 'lists the overview and every child and marks only the current page' do
      out = described_class.render(page, 'board.html')
      expect(out.scan('nav-link').size).to eq(6)
      expect(out.scan('aria-current="page" href').size).to eq(1)
      expect(out).to include('<a class="nav-link active" aria-current="page" href="board.html">Board</a>')
    end

    it 'renders both regions empty for a page outside every section' do
      out = described_class.render(page, 'index.html')
      expect(out).not_to include('breadcrumb-item')
      expect(out).not_to include('nav-link')
    end

    it 'is idempotent' do
      once = described_class.render(page, 'board.html')
      expect(described_class.render(once, 'board.html')).to eq(once)
    end
  end
  end
end
