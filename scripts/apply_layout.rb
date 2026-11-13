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
# layout/site-nav.yml: meta (<title>, description, canonical, Open Graph and Twitter tags, BreadcrumbList JSON-LD), breadcrumb and section-nav; and the social region (layout/socials.yml; the header partial gets the same
# accounts through its {{social-links}} token). Everything outside the markers is left alone.
# In the nav region the link to the page being written gets class="... active" and aria-current="page" (and so does its dropdown toggle).
#
#   ruby scripts/apply_layout.rb            rewrite every page that has markers
#   ruby scripts/apply_layout.rb --check    exit 1 and list pages that differ (CI drift check); writes nothing
#   ruby scripts/apply_layout.rb a.html     only the named pages
require 'yaml'
require 'cgi'
require 'digest'
require 'json'

module ApplyLayout
  ROOT = File.expand_path('..', __dir__)
  PARTIALS = File.join(ROOT, 'layout', 'partials')
  REGIONS = %w[head header nav footer].freeze
  GENERATED = %w[meta breadcrumb section-nav social].freeze
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
    basename == registry.first['file'] ? "#{site['url']}/" : "#{site['url']}/#{basename}"
  end

  # <title>, description, canonical link and BreadcrumbList JSON-LD for a registered page ('' for any other file).
  def meta(basename)
    page = entry(basename)
    return '' unless page

    out = +"<title>#{CGI.escapeHTML(page_title(basename))}</title>\n"
    out << %(<meta name="description" content="#{CGI.escapeHTML(page['description'])}">\n)
    out << %(<link rel="canonical" href="#{canonical_url(basename)}">\n)
    out << social_meta(page, basename)
    out << breadcrumb_jsonld(basename)
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

  def breadcrumb_jsonld(basename)
    chain = trail(basename)
    return '' if chain.size <= 1

    data = {
      '@context' => 'https://schema.org', '@type' => 'BreadcrumbList',
      'itemListElement' => chain.each_with_index.map do |p, i|
        { '@type' => 'ListItem', 'position' => i + 1, 'name' => p['name'], 'item' => canonical_url(p['file']) }
      end
    }
    %(<script type="application/ld+json">\n#{JSON.pretty_generate(data).gsub('</', '<\\/')}\n</script>\n)
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
    items = children(sec['file']).map do |c|
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
        body = { 'meta' => meta(basename), 'breadcrumb' => breadcrumb(basename), 'section-nav' => section_nav(basename), 'social' => social_links(:list) }.fetch(name)
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
