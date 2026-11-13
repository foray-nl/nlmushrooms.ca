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

  describe '404 page' do
    let(:src) { File.read(File.join(described_class::ROOT, '404.html'), encoding: 'UTF-8') }

    it 'uses the shared head, header, nav and footer and resolves links from the site root' do
      %w[head header nav footer].each { |r| expect(src).to include("<!-- layout:#{r} -->") }
      expect(src).to include('<base href="/">')
      expect(src).to include('<meta name="robots" content="noindex">')
      expect(src).not_to include('<!-- layout:meta -->')
    end
  end

  describe 'page registry (layout/site-nav.yml)' do
    # 404.html shares the static regions but is not a registered page: no canonical, breadcrumb or sitemap entry.
    let(:converted) do
      described_class.pages.select { |f| File.read(f, encoding: 'UTF-8').include?('<!-- layout:head -->') }.map { |f| File.basename(f) } - ['404.html']
    end
    let(:registered) { described_class.registry.map { |p| p['file'] } }

    it 'lists every converted page and no file that does not exist' do
      expect(converted - registered).to be_empty
      expect(registered.reject { |f| File.exist?(File.join(described_class::ROOT, f)) }).to be_empty
    end

    it 'gives every page except the home page a registered parent, with no cycles and no duplicates' do
      expect(registered.uniq).to eq(registered)
      described_class.registry.drop(1).each do |p|
        expect(registered).to include(p['parent']), "#{p['file']} has no registered parent"
        expect(described_class.trail(p['file']).first['file']).to eq(registered.first)
      end
    end

    it 'has a unique description of 70 to 160 characters for every page' do
      descriptions = described_class.registry.map { |p| p['description'].to_s }
      expect(descriptions.uniq.size).to eq(descriptions.size)
      descriptions.each { |d| expect(d.length).to be_between(70, 160).inclusive }
    end

    it 'puts the generated meta region and a breadcrumb region on every converted page' do
      converted.each do |f|
        src = File.read(File.join(described_class::ROOT, f), encoding: 'UTF-8')
        expect(src).to include('<!-- layout:meta -->'), "#{f} lacks the meta region"
        expect(src).to include('<!-- layout:breadcrumb -->') unless f == registered.first
        expect(src).not_to match(%r{<title>(?!.*Foray Newfoundland and Labrador</title>)}), "#{f} has a hand-written title"
      end
    end

    it 'builds titles that nest the parents under the site name' do
      expect(described_class.page_title('index.html')).to eq('Foray Newfoundland and Labrador')
      expect(described_class.page_title('foray_2026.html')).to eq('Foray 2026 | Foray Newfoundland and Labrador')
      expect(described_class.page_title('contacts.html')).to eq('Contact Us | About Us | Foray Newfoundland and Labrador')
      expect(described_class.page_title('board.html')).to eq('Board of Directors | About Us | Foray Newfoundland and Labrador')
    end

    it 'emits a canonical apex URL and a BreadcrumbList that matches the visible crumbs' do
      described_class.registry.drop(1).each do |p|
        out = described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n<!-- layout:breadcrumb -->\n<!-- /layout:breadcrumb -->\n", p['file'])
        expect(out).to include(%(<link rel="canonical" href="https://nlmushrooms.ca/#{p['file']}">))
        graph = JSON.parse(out[%r{<script type="application/ld\+json">\n(.*?)\n</script>}m, 1])['@graph']
        json = graph.find { |n| n['@type'] == 'BreadcrumbList' }
        names = json['itemListElement'].map { |i| i['name'] }
        visible = out.scan(%r{<li class="breadcrumb-item[^"]*"[^>]*>(?:<a [^>]*>)?([^<]+)}).flatten.map { |n| CGI.unescapeHTML(n) }
        expect(json['@type']).to eq('BreadcrumbList')
        expect(names).to eq(visible)
        expect(json['itemListElement'].map { |i| i['position'] }).to eq((1..names.size).to_a)
        expect(json['itemListElement'].map { |i| i['item'] }).to all(start_with('https://nlmushrooms.ca/'))
      end
    end

    it 'has no breadcrumb and no BreadcrumbList on the home page, and a bare canonical' do
      out = described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n", 'index.html')
      expect(out).not_to include('BreadcrumbList')
      expect(out).to include('"@type": "WebPage"')
      expect(out).to include('href="https://nlmushrooms.ca/"')
    end
  end

  describe 'Open Graph and Twitter tags' do
    def jpeg_size(path)
      data = File.binread(path)
      i = 2
      while i < data.size
        marker = data.getbyte(i + 1)
        len = data[i + 2, 2].unpack1('n')
        return data[i + 5, 4].unpack('nn').reverse if (0xC0..0xC3).cover?(marker)

        i += 2 + len
      end
    end

    it 'gives every registered page a complete, consistent og:/twitter: block with an existing 1200x630 image' do
      described_class.registry.each do |p|
        out = described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n", p['file'])
        tag = ->(k) { CGI.unescapeHTML(out[/<meta property="#{k}" content="([^"]*)"/, 1].to_s) }
        expect(tag['og:title']).to eq(described_class.page_title(p['file']))
        expect(tag['og:description']).to eq(p['description'])
        expect(tag['og:url']).to eq(described_class.canonical_url(p['file']))
        expect(tag['og:site_name']).to eq(described_class.site['name'])
        expect(tag['og:locale']).to eq('en_CA')
        expect(tag['og:image:alt']).not_to be_empty
        expect(out).to include('<meta name="twitter:card" content="summary_large_image">')
        image = tag['og:image']
        expect(image).to start_with('https://nlmushrooms.ca/images/share/')
        file = File.join(described_class::ROOT, image.sub('https://nlmushrooms.ca/', ''))
        expect(File).to exist(file)
        expect(jpeg_size(file)).to eq([1200, 630])
      end
    end

    it 'uses the poster as the share image on the foray pages and the logo elsewhere' do
      expect(described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n", 'foray_2026.html')).to include('images/share/foray-2026.jpg')
      expect(described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n", 'contacts.html')).to include('images/share/default.jpg')
    end
  end

  describe 'JSON-LD graph' do
    def graph_for(file)
      out = described_class.render("<!-- layout:meta -->\n<!-- /layout:meta -->\n", file)
      JSON.parse(out[%r{<script type="application/ld\+json">\n(.*?)\n</script>}m, 1])
    end

    it 'is valid JSON with Organization, WebSite and a page node on every registered page' do
      described_class.registry.each do |p|
        data = graph_for(p['file'])
        graph = data['@graph']
        expect(data['@context']).to eq('https://schema.org')
        types = graph.map { |n| n['@type'] }
        expect(types).to include('Organization', 'WebSite')
        page = graph.find { |n| n['@id'] == "#{described_class.canonical_url(p['file'])}#webpage" }
        expect(page).not_to be_nil
        expect(page['@type']).to eq(p['schema_type'] || 'WebPage')
        expect(page['url']).to eq(described_class.canonical_url(p['file']))
        expect(page['description']).to eq(p['description'])
      end
    end

    it 'resolves every @id reference to a node in the same graph and uses absolute URLs' do
      described_class.registry.each do |p|
        graph = graph_for(p['file'])['@graph']
        ids = graph.map { |n| n['@id'] }
        refs = JSON.generate(graph).scan(/"([a-z]+)":\{"@id":"([^"]+)"\}/).map(&:last)
        expect(refs - ids).to be_empty, "#{p['file']}: unresolved #{refs - ids}"
        urls = JSON.generate(graph).scan(/"(?:url|item|logo)":"([^"]+)"/).flatten
        expect(urls).to all(start_with('https://nlmushrooms.ca/'))
      end
    end

    it 'describes the organization from the registry and the social accounts' do
      org = graph_for('index.html')['@graph'].find { |n| n['@type'] == 'Organization' }
      expect(org['legalName']).to eq('Mushroom Foray Newfoundland and Labrador Inc.')
      expect(org['sameAs']).to eq(described_class.socials.map { |a| a['url'] })
      expect(org['telephone']).to match(/\A\+1-\d{3}-\d{3}-\d{4}\z/)
      expect(org['address']).not_to have_key('streetAddress')
      expect(File).to exist(File.join(described_class::ROOT, org['logo'].sub('https://nlmushrooms.ca/', '')))
    end

    it 'types the About and Contact pages and links child pages to their breadcrumb' do
      expect(graph_for('about_us.html')['@graph'].map { |n| n['@type'] }).to include('AboutPage')
      expect(graph_for('contacts.html')['@graph'].map { |n| n['@type'] }).to include('ContactPage')
      page = graph_for('mission.html')['@graph'].find { |n| n['@id'].end_with?('#webpage') }
      expect(page['breadcrumb']['@id']).to eq('https://nlmushrooms.ca/mission.html#breadcrumb')
    end
  end
end
