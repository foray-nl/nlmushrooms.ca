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

    it 'builds the sub-nav with the section title and every child, marking only the current page' do
      out = described_class.render(page, 'board.html')
      expect(out).to include('<a class="subnav-title" href="about_us.html">About Us</a>')
      expect(out.scan('class="nav-link').size).to eq(5)
      expect(out.scan('aria-current="page" href').size).to eq(1)
      expect(out).to include('<a class="nav-link active" aria-current="page" href="board.html">Board</a>')
    end

    it 'marks the section title active on the overview page' do
      out = described_class.render(page, 'about_us.html')
      expect(out).to include('<a class="subnav-title active" aria-current="page" href="about_us.html">About Us</a>')
      expect(out).not_to include('nav-link active')
    end

    it 'renders both regions empty for a page outside every section' do
      out = described_class.render(page, 'index.html')
      expect(out).not_to include('breadcrumb-item')
      expect(out).not_to include('subnav')
    end

    it 'is idempotent' do
      once = described_class.render(page, 'board.html')
      expect(described_class.render(once, 'board.html')).to eq(once)
    end
  end
  end

  describe 'asset cache busting' do
    # netlify.toml caches these paths for a year as immutable, so every reference must carry the current content digest.
    it 'versions every reference to an immutable asset with its current digest' do
      refs = Dir.glob(File.join(described_class::ROOT, '*.html')).flat_map do |file|
        File.read(file, encoding: 'UTF-8').scan(%r{(?:href|src)="(assets/(?:vendor/|scripts/|styles/site\.css)[^"]*)"}).flatten.map { |r| [File.basename(file), r] }
      end
      stale = refs.reject do |_, ref|
        path, version = ref.split('?v=')
        version && version == Digest::SHA256.file(File.join(described_class::ROOT, path)).hexdigest[0, 10]
      end
      expect(refs).not_to be_empty
      expect(stale).to be_empty, "run ruby scripts/apply_layout.rb; unversioned or stale: #{stale.inspect}"
    end

    it 'sets immutable caching only on paths whose references are versioned' do
      toml = File.read(File.join(described_class::ROOT, 'netlify.toml'))
      expect(toml).to include('for = "/assets/vendor/*"', 'for = "/assets/scripts/*"', 'for = "/assets/styles/site.css"', 'max-age=31536000, immutable')
      expect(toml).not_to match(%r{for = "/\*"})
    end
  end

  describe 'social links' do
    let(:header) { described_class.render("<!-- layout:header -->\n<!-- /layout:header -->\n", 'index.html') }

    it 'renders every account as an accessible, tooltipped icon link in the header' do
      described_class.socials.each do |a|
        expect(header).to include(%(href="#{a['url']}"), %(title="#{a['platform']}: #{a['handle']}"),
                                  %(aria-label="#{a['platform']}: #{a['handle']} (opens in a new tab)"), %(<i class="fa-brands #{a['icon']}" aria-hidden="true">))
      end
      expect(header.scan('data-bs-toggle="tooltip"').size).to eq(3)
      expect(header.scan('rel="noopener noreferrer"').size).to eq(3)
      expect(header).to include('aria-label="Foray NL on social media"')
    end

    it 'renders the Contacts list with visible platform and handle' do
      out = described_class.render("<!-- layout:social -->\n<!-- /layout:social -->\n", 'contacts.html')
      expect(out).to include('social-platform">Facebook', 'social-handle">ForayNL', 'social-handle">@foraynl', 'social-handle">foray_nl')
    end

    it 'only uses glyphs present in the vendored Font Awesome subset' do
      css = File.read(File.join(described_class::ROOT, 'assets/vendor/fontawesome/fontawesome-social.css'))
      described_class.socials.each { |a| expect(css).to include(".#{a['icon']}::before") }
    end
  end
end
