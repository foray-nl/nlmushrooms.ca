#!/usr/bin/env ruby
# frozen_string_literal: true

# Rewrites the shared regions of each page from layout/partials/*.html.
#
# A page opts in by wrapping a region in marker comments (indentation of the opening marker is kept):
#
#   <!-- layout:nav -->
#   ...anything, replaced on every run...
#   <!-- /layout:nav -->
#
# Regions: head (shared <link>s), header, nav, footer, plus generated regions built from the page registry
# layout/site-nav.yml: meta (<title>, description, canonical, Open Graph and Twitter tags, JSON-LD graph), breadcrumb and section-nav; and the social region (layout/socials.yml; the header partial gets the same
# accounts through its {{social-links}} token); the issues (a volume page's covers) and volumes (the Omphalina overview list) regions from layout/omphalina.yml; and the forays and reports regions (layout/forays.yml: the Past Forays directory and the report list). Forays with their own page also get Event JSON-LD. Everything outside the markers is left alone.
# In the nav region the link to the page being written gets class="... active" and aria-current="page" (and so does its dropdown toggle).
#
#   ruby scripts/apply_layout.rb            rewrite every page that has markers
#   ruby scripts/apply_layout.rb --check    exit 1 and list pages that differ (CI drift check); writes nothing
#   ruby scripts/apply_layout.rb a.html     only the named pages
require 'yaml'
require 'cgi'
require 'digest'
require 'json'
require 'date'

module ApplyLayout
  ROOT = File.expand_path('..', __dir__)
  PARTIALS = File.join(ROOT, 'layout', 'partials')
  REGIONS = %w[head header nav footer].freeze
  GENERATED = %w[meta breadcrumb section-nav social forays reports issues volumes].freeze
  OMPHALINA = File.join(ROOT, 'layout', 'omphalina.yml')
  FORAYS = File.join(ROOT, 'layout', 'forays.yml')
  SOCIALS = File.join(ROOT, 'layout', 'socials.yml')
  HIERARCHY = File.join(ROOT, 'layout', 'site-nav.yml')
  SHARE_SIZE = [1200, 630].freeze

  module_function

  def pages
    Dir.glob(File.join(ROOT, '**', '*.html')).reject { |f| f.sub("#{ROOT}/", '').start_with?('tmp/', 'vendor/', 'layout/') }.sort
  end

  def partial(name)
    File.read(File.join(PARTIALS, "#{name}.html"), encoding: 'UTF-8')
  end

  # Local stylesheet and script URLs in the head get ?v=<content hash> so a browser or CDN holding an older copy
  # (Netlify serves assets with max-age=14400) fetches the new file as soon as the page's HTML changes.
  def version_assets(html)
    html.gsub(%r{(href|src)="(assets/[^"?]+\.(?:css|js))"}) do
      attr = Regexp.last_match(1)
      path = Regexp.last_match(2)
      %(#{attr}="#{path}?v=#{Digest::SHA256.file(File.join(ROOT, path)).hexdigest[0, 10]}")
    end
  end

  def hierarchy
    @hierarchy ||= YAML.safe_load_file(HIERARCHY)
  end

  def site = hierarchy['site']
  def registry = hierarchy['pages']
  def entry(basename) = registry.find { |p| p['file'] == basename }
  def children(file) = registry.select { |p| p['parent'] == file }
  def segment(page) = page['title'] || page['name']

  # [home, ..., page] for a registered page, [] for any other file.
  def trail(basename)
    page = entry(basename)
    chain = []
    while page
      chain.unshift(page)
      page = entry(page['parent'].to_s)
    end
    chain
  end

  # The page whose children form the sub-nav this page shows (itself or its parent), or nil.
  def section_for(basename)
    page = entry(basename)
    return nil unless page
    return page if page['subnav']

    parent = entry(page['parent'].to_s)
    parent if parent && parent['subnav']
  end

  # "Contact Us | About Us | Foray Newfoundland and Labrador"; the home page is the site name alone.
  def page_title(basename)
    chain = trail(basename)
    return site['name'] if chain.size <= 1

    (chain.drop(1).reverse.map { |p| segment(p) } + [site['name']]).join(' | ')
  end

  def canonical_url(basename)
    basename == registry.first['file'] ? "#{site['url']}/" : "#{site['url']}/#{basename.gsub(' ', '%20')}"
  end

  # <title>, description, canonical link and BreadcrumbList JSON-LD for a registered page ('' for any other file).
  def meta(basename)
    page = entry(basename)
    return '' unless page

    out = +"<title>#{CGI.escapeHTML(page_title(basename))}</title>\n"
    out << %(<meta name="description" content="#{CGI.escapeHTML(page['description'])}">\n)
    out << %(<link rel="canonical" href="#{canonical_url(basename)}">\n)
    out << social_meta(page, basename)
    out << jsonld(basename)
    out
  end

  # Open Graph and Twitter card tags. Twitter falls back to the og:* values, so only the card type is needed.
  def social_meta(page, basename)
    image = page['image'] || site['image']
    alt = page['image_alt'] || site['image_alt']
    tags = [
      ['property', 'og:type', 'website'], ['property', 'og:site_name', site['name']],
      ['property', 'og:locale', site['locale']], ['property', 'og:title', page_title(basename)],
      ['property', 'og:description', page['description']], ['property', 'og:url', canonical_url(basename)],
      ['property', 'og:image', "#{site['url']}/#{image}"], ['property', 'og:image:width', SHARE_SIZE[0].to_s],
      ['property', 'og:image:height', SHARE_SIZE[1].to_s], ['property', 'og:image:alt', alt],
      ['name', 'twitter:card', 'summary_large_image']
    ]
    tags.map { |attr, key, value| %(<meta #{attr}="#{key}" content="#{CGI.escapeHTML(value)}">\n) }.join
  end

  # One JSON-LD @graph per page: Organization, WebSite, the page itself (AboutPage, ContactPage, ... via the registry's
  # `schema_type`, default WebPage) and, below the home page, its BreadcrumbList. Nodes reference each other by @id.
  def jsonld(basename)
    graph = [organization, website, webpage(basename)]
    crumbs = breadcrumb_list(basename)
    graph << crumbs if crumbs
    ev = event(basename)
    graph << ev if ev
    data = { '@context' => 'https://schema.org', '@graph' => graph }
    %(<script type="application/ld+json">\n#{JSON.pretty_generate(data).gsub('</', '<\\/')}\n</script>\n)
  end

  def org_id = "#{site['url']}/#organization"
  def website_id = "#{site['url']}/#website"

  def organization
    org = site['organization']
    {
      '@type' => 'Organization', '@id' => org_id, 'name' => site['name'], 'legalName' => org['legal_name'],
      'url' => "#{site['url']}/", 'logo' => "#{site['url']}/#{org['logo']}", 'email' => org['email'],
      'telephone' => org['telephone'],
      'address' => { '@type' => 'PostalAddress', 'addressLocality' => org['locality'], 'addressRegion' => org['region'],
                     'addressCountry' => org['country'] },
      'sameAs' => socials.map { |a| a['url'] }
    }
  end

  def website
    { '@type' => 'WebSite', '@id' => website_id, 'url' => "#{site['url']}/", 'name' => site['name'],
      'inLanguage' => 'en-CA', 'publisher' => { '@id' => org_id } }
  end

  def webpage(basename)
    page = entry(basename)
    url = canonical_url(basename)
    node = {
      '@type' => page['schema_type'] || 'WebPage', '@id' => "#{url}#webpage", 'url' => url,
      'name' => trail(basename).size > 1 ? segment(page) : site['name'], 'description' => page['description'], 'inLanguage' => 'en-CA',
      'isPartOf' => { '@id' => website_id }, 'about' => { '@id' => org_id }
    }
    node['breadcrumb'] = { '@id' => "#{url}#breadcrumb" } if trail(basename).size > 1
    vol = volume_for(basename)
    if vol
      node['mainEntity'] = { '@type' => 'PublicationVolume', 'volumeNumber' => vol['volume'].to_s, 'datePublished' => vol['year'].to_s,
                             'name' => "Omphalina #{volume_label(vol)}", 'isPartOf' => { '@type' => 'Periodical', 'name' => 'Omphalina', 'publisher' => { '@id' => org_id } } }
    end
    node
  end

  def breadcrumb_list(basename)
    chain = trail(basename)
    return nil if chain.size <= 1

    { '@type' => 'BreadcrumbList', '@id' => "#{canonical_url(basename)}#breadcrumb",
      'itemListElement' => chain.each_with_index.map do |p, i|
        { '@type' => 'ListItem', 'position' => i + 1, 'name' => p['name'], 'item' => canonical_url(p['file']) }
      end }
  end

  def forays
    @forays ||= YAML.safe_load_file(FORAYS, permitted_classes: [Date]).sort_by { |f| -f['year'] }
  end

  def foray_for(basename) = forays.find { |f| f['page'] == basename }
  def long_date(date) = date.strftime('%B %-d, %Y')

  # "October 2-4, 2026", "September 29 to October 1, 2023", "From September 10, 2010" or nil when no date is known.
  def date_text(foray)
    from = foray['start']
    to = foray['end']
    return nil unless from
    return "From #{long_date(from)}" unless to
    return long_date(from) if from == to
    return "#{from.strftime('%B %-d')}-#{to.strftime('%-d, %Y')}" if from.month == to.month

    "#{from.strftime('%B %-d')} to #{to.strftime('%B %-d, %Y')}"
  end

  def date_attr(foray)
    return nil unless foray['start']

    foray['end'] && foray['end'] != foray['start'] ? "#{foray['start']}/#{foray['end']}" : foray['start'].to_s
  end

  def report_online?(foray) = foray['report'] && File.exist?(File.join(ROOT, foray['report']))

  def report_label(foray)
    foray['report'].start_with?('omphaline/') ? 'Report (PDF, in an Omphalina issue)' : 'Report (PDF)'
  end

  DEFAULT_CARD = { 'file' => 'default', 'alt' => 'Foray Newfoundland and Labrador logo: a chanterelle mushroom beside the words Foray Newfoundland and Labrador' }.freeze
  STATUS_TEXT = { 'cancelled' => 'In-person foray cancelled', 'not_held' => 'Not held' }.freeze

  # [file stem, alt] of a foray's card image; the default banner card when it has no art.
  def card_image(foray)
    year = foray['report_image_year'] || foray['year']
    source = forays.find { |f| f['year'] == year }
    return [DEFAULT_CARD['file'], DEFAULT_CARD['alt']] unless source['art'] && File.exist?(File.join(ROOT, 'images', 'forays', "#{year}.jpg"))

    [year.to_s, source['art_alt'].to_s]
  end

  def pdf_href(path) = CGI.escapeHTML(path).gsub(' ', '%20')

  # Past Forays directory: one card per foray, newest first, with poster or report cover, dates, place and links.
  def foray_directory
    cards = forays.map do |f|
      img, alt = card_image(f.merge('report_image_year' => nil))
      out = +%(  <li class="foray-card" id="foray-#{f['year']}">\n)
      out << %(    <img src="images/forays/#{img}.jpg" alt="#{CGI.escapeHTML(alt)}" width="420" height="544" decoding="async">\n)
      out << %(    <div class="foray-card-body">\n)
      title = CGI.escapeHTML(f['name'])
      title = %(<a href="#{f['page']}">#{title}</a>) if f['page']
      out << %(      <h3>#{title}</h3>\n)
      out << %(      <p class="foray-status">#{STATUS_TEXT[f['status']]}</p>\n) if STATUS_TEXT[f['status']]
      place = [f['venue'], f['area']].compact.join(', ')
      out << %(      <p class="foray-place">#{CGI.escapeHTML(place)}</p>\n) unless place.empty?
      dates = date_text(f)
      out << %(      <p class="foray-dates"><time datetime="#{date_attr(f)}">#{dates}</time></p>\n) if dates
      out << %(      <p>#{CGI.escapeHTML(f['blurb'])}</p>\n) if f['blurb']
      if f['report'] && report_online?(f)
        out << %(      <p class="foray-links"><a href="#{pdf_href(f['report'])}">#{report_label(f)}</a></p>\n)
      elsif f['report']
        out << %(      <p class="foray-links">Report not currently online</p>\n)
      end
      out << %(    </div>\n  </li>\n)
    end
    %(<ul class="foray-directory">\n#{cards.join}</ul>\n)
  end

  # Every foray report available for download, newest first, as media cards: text left, report cover right.
  def report_list
    rows = forays.select { |f| f['report'] }.map do |f|
      img, alt = card_image(f)
      place = [f['venue'], f['area']].compact.join(', ')
      link = if report_online?(f)
               %(<a class="stretched-link" href="#{pdf_href(f['report'])}">#{report_label(f)}</a>)
             else
               'Not currently online'
             end
      out = +%(  <li class="media-card">\n    <div class="media-card-body">\n)
      out << %(      <h3>#{f['year']}</h3>\n)
      out << %(      <p>#{CGI.escapeHTML(place)}</p>\n) unless place.empty?
      out << %(      <p class="media-card-link">#{link}</p>\n    </div>\n)
      out << %(    <img class="media-card-img" src="images/forays/#{img}.jpg" alt="#{CGI.escapeHTML(alt)}" width="420" height="544" decoding="async">\n  </li>\n)
    end
    %(<ul class="report-list">\n#{rows.join}</ul>\n)
  end

  def omphalina
    @omphalina ||= YAML.safe_load_file(OMPHALINA).sort_by { |v| -v['volume'] }
  end

  def volume_for(basename) = omphalina.find { |v| v['page'] == basename }

  # Width and height of a PNG from its header, so thumbnails reserve their space.
  def png_size(path)
    File.binread(File.join(ROOT, path), 24)[16, 8].unpack('NN')
  end

  def volume_label(vol) = "Volume #{vol['volume']} (#{vol['year']})"

  # Cover grid for one volume page: each cover links to the issue PDF.
  def issue_grid(basename)
    vol = volume_for(basename)
    return '' unless vol

    cards = vol['issues'].map do |i|
      w, h = png_size(i['thumb'])
      label = "Volume #{vol['volume']}, Issue #{i['issue']}"
      %(  <li class="issue-card"><a href="#{pdf_href(i['pdf'])}" target="_blank" rel="noopener noreferrer"><img src="#{i['thumb']}" alt="Cover of Omphalina #{label}" width="#{w}" height="#{h}" decoding="async"><span class="issue-label">#{label}<span class="visually-hidden"> (PDF, opens in a new tab)</span></span></a></li>\n)
    end
    %(<ul class="issue-grid">\n#{cards.join}</ul>\n)
  end

  # Volume list for the Omphalina overview: one media card per volume, newest first, first cover on the right.
  def volume_list
    cards = omphalina.map do |v|
      first = v['issues'].first
      w, h = png_size(first['thumb'])
      count = v['issues'].size
      out = +%(  <li class="media-card">\n    <div class="media-card-body">\n)
      out << %(      <h3>#{volume_label(v)}</h3>\n      <p>#{count} #{count == 1 ? 'issue' : 'issues'}</p>\n)
      out << %(      <p class="media-card-link"><a class="stretched-link" href="#{v['page']}">Browse Volume #{v['volume']}</a></p>\n    </div>\n)
      out << %(    <img class="media-card-img" src="#{first['thumb']}" alt="" width="#{w}" height="#{h}" decoding="async">\n  </li>\n)
    end
    %(<ul class="report-list">\n#{cards.join}</ul>\n)
  end

  # schema.org Event for a foray that has its own page.
  def event(basename)
    f = foray_for(basename)
    return nil unless f && f['start'] && f['end']

    url = canonical_url(basename)
    page = entry(basename)
    node = {
      '@type' => 'Event', '@id' => "#{url}#event", 'name' => "#{f['name']}: #{site['name']}",
      'startDate' => f['start'].to_s, 'endDate' => f['end'].to_s,
      'eventStatus' => "https://schema.org/#{f['status'] == 'cancelled' ? 'EventCancelled' : 'EventScheduled'}",
      'eventAttendanceMode' => 'https://schema.org/OfflineEventAttendanceMode',
      'description' => page['description'], 'image' => "#{site['url']}/#{page['image'] || site['image']}",
      'organizer' => { '@id' => org_id }, 'url' => url
    }
    node['location'] = { '@type' => 'Place', 'name' => f['venue'] || f['area'],
                         'address' => { '@type' => 'PostalAddress', 'addressRegion' => 'NL', 'addressCountry' => 'CA' } }
    node
  end

  def socials
    @socials ||= YAML.safe_load_file(SOCIALS)
  end

  # Header variant: icon-only links with a Bootstrap tooltip ("Platform: handle") and a full accessible name.
  # List variant (Contacts page): icon plus visible platform and handle, so no tooltip is needed.
  def social_links(variant)
    if variant == :header
      items = socials.map do |a|
        label = "#{a['platform']}: #{CGI.escapeHTML(a['handle'])}"
        %(    <li><a class="social-link" href="#{a['url']}" target="_blank" rel="noopener noreferrer" data-bs-toggle="tooltip" data-bs-placement="bottom" title="#{label}" aria-label="#{label} (opens in a new tab)"><i class="fa-brands #{a['icon']}" aria-hidden="true"></i></a></li>\n)
      end
      %(<nav class="social-links" aria-label="Foray NL on social media">\n  <ul>\n#{items.join}  </ul>\n</nav>\n)
    else
      items = socials.map do |a|
        %(  <li><a href="#{a['url']}" target="_blank" rel="noopener noreferrer"><i class="fa-brands #{a['icon']}" aria-hidden="true"></i> <span class="social-platform">#{a['platform']}</span> <span class="social-handle">#{CGI.escapeHTML(a['handle'])}</span><span class="visually-hidden"> (opens in a new tab)</span></a></li>\n)
      end
      %(<ul class="social-list">\n#{items.join}</ul>\n)
    end
  end

  def breadcrumb(basename)
    chain = trail(basename)
    return '' if chain.size <= 1

    items = chain.each_with_index.map do |page, i|
      if i == chain.size - 1
        %(    <li class="breadcrumb-item active" aria-current="page">#{CGI.escapeHTML(page['name'])}</li>\n)
      else
        %(    <li class="breadcrumb-item"><a href="#{page['file']}">#{CGI.escapeHTML(page['name'])}</a></li>\n)
      end
    end
    %(<nav class="page-breadcrumb" aria-label="breadcrumb">\n  <ol class="breadcrumb">\n#{items.join}  </ol>\n</nav>\n)
  end

  # Horizontal sub-nav shown between the main nav and the page: the section title (links to its overview) and children.
  def section_nav(basename)
    sec = section_for(basename)
    return '' unless sec

    title_cls = sec['file'] == basename ? 'subnav-title active' : 'subnav-title'
    title_cur = sec['file'] == basename ? ' aria-current="page"' : ''
    items = children(sec['file']).reject { |c| c['subnav_hidden'] }.map do |c|
      active = c['file'] == basename
      cls = active ? 'nav-link active' : 'nav-link'
      cur = active ? ' aria-current="page"' : ''
      %(    <li class="nav-item"><a class="#{cls}"#{cur} href="#{c['file']}">#{CGI.escapeHTML(c['name'])}</a></li>\n)
    end
    label = CGI.escapeHTML(sec['name'])
    %(<nav class="subnav" aria-label="#{label} section">\n  <a class="#{title_cls}"#{title_cur} href="#{sec['file']}">#{label}</a>\n  <ul class="nav">\n#{items.join}  </ul>\n</nav>\n)
  end

  def render(source, page_path)
    basename = File.basename(page_path)
    source = render_generated(source, basename)
    REGIONS.reduce(source) do |text, name|
      text.gsub(region_pattern(name)) do
        indent = Regexp.last_match(1)
        body = partial(name)
        body = body.gsub('{{social-links}}') { social_links(:header).lines.map { |l| "  #{l}" }.join.lstrip } if name == 'header'
        body = mark_active(body, File.basename(page_path)) if name == 'nav'
        body = version_assets(body) if name == 'head'
        lines = body.lines.map { |l| l.strip.empty? ? l : "#{indent}#{l}" }.join
        "#{indent}<!-- layout:#{name} -->\n#{lines}#{indent}<!-- /layout:#{name} -->\n"
      end
    end
  end

  def render_generated(source, basename)
    GENERATED.reduce(source) do |text, name|
      text.gsub(region_pattern(name)) do
        indent = Regexp.last_match(1)
        body = { 'meta' => meta(basename), 'breadcrumb' => breadcrumb(basename), 'section-nav' => section_nav(basename), 'social' => social_links(:list), 'forays' => foray_directory, 'reports' => report_list, 'issues' => issue_grid(basename), 'volumes' => volume_list }.fetch(name)
        lines = body.lines.map { |l| "#{indent}#{l}" }.join
        "#{indent}<!-- layout:#{name} -->\n#{lines}#{indent}<!-- /layout:#{name} -->\n"
      end
    end
  end

  def region_pattern(name)
    /^([ \t]*)<!-- layout:#{name} -->\n.*?^\1<!-- \/layout:#{name} -->\n/m
  end

  # Marks the link to the page being written, and the dropdown toggle that contains it.
  def mark_active(nav, basename)
    name = Regexp.escape(basename)
    nav = nav.gsub(/<a class="(nav-link|dropdown-item)" href="#{name}"/) do
      %(<a class="#{Regexp.last_match(1)} active" aria-current="page" href="#{basename}")
    end
    nav.gsub(%r{<li class="nav-item dropdown">.*?</ul>\s*</li>}m) do |block|
      block.include?('dropdown-item active') ? block.sub('class="nav-link dropdown-toggle"', 'class="nav-link dropdown-toggle active"') : block
    end
  end

  def run(argv)
    check = argv.delete('--check')
    files = argv.empty? ? pages : argv.map { |f| File.expand_path(f) }
    drifted = []
    files.each do |file|
      source = File.read(file, encoding: 'UTF-8')
      next unless source.include?('<!-- layout:')

      output = render(source, file)
      next if output == source

      drifted << file.sub("#{ROOT}/", '')
      File.write(file, output) unless check
    end
    report(drifted, check)
  end

  def report(drifted, check)
    if check
      warn "Layout drift (run ruby scripts/apply_layout.rb): #{drifted.join(', ')}" unless drifted.empty?
      return drifted.empty? ? 0 : 1
    end
    puts drifted.empty? ? 'Layout up to date.' : "Updated: #{drifted.join(', ')}"
    0
  end
end

exit(ApplyLayout.run(ARGV)) if $PROGRAM_NAME == __FILE__
