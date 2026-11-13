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
# Regions: head (shared <link>s), header, nav, footer, plus the generated breadcrumb and section-nav regions (built from
# layout/site-nav.yml for pages listed there) and the social region (layout/socials.yml; the header partial gets the same
# accounts through its {{social-links}} token). Everything outside the markers is left alone.
# In the nav region the link to the page being written gets class="... active" and aria-current="page" (and so does its dropdown toggle).
#
#   ruby scripts/apply_layout.rb            rewrite every page that has markers
#   ruby scripts/apply_layout.rb --check    exit 1 and list pages that differ (CI drift check); writes nothing
#   ruby scripts/apply_layout.rb a.html     only the named pages
require 'yaml'
require 'cgi'
require 'digest'

module ApplyLayout
  ROOT = File.expand_path('..', __dir__)
  PARTIALS = File.join(ROOT, 'layout', 'partials')
  REGIONS = %w[head header nav footer].freeze
  GENERATED = %w[breadcrumb section-nav social].freeze
  SOCIALS = File.join(ROOT, 'layout', 'socials.yml')
  HIERARCHY = File.join(ROOT, 'layout', 'site-nav.yml')

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

  # The section a page belongs to (as overview or child), or nil.
  def section_for(basename)
    hierarchy['sections'].find do |sec|
      sec['page'] == basename || sec['children'].any? { |c| c['page'] == basename }
    end
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
    sec = section_for(basename)
    return '' unless sec

    crumbs = [[hierarchy['home_title'] || 'Home', hierarchy['home']], [sec['title'], sec['page']]]
    child = sec['children'].find { |c| c['page'] == basename }
    crumbs << [child['title'], child['page']] if child
    items = crumbs.each_with_index.map do |(title, href), i|
      if i == crumbs.size - 1
        %(    <li class="breadcrumb-item active" aria-current="page">#{CGI.escapeHTML(title)}</li>\n)
      else
        %(    <li class="breadcrumb-item"><a href="#{href}">#{CGI.escapeHTML(title)}</a></li>\n)
      end
    end
    %(<nav class="page-breadcrumb" aria-label="breadcrumb">\n  <ol class="breadcrumb">\n#{items.join}  </ol>\n</nav>\n)
  end

  # Horizontal sub-nav shown between the main nav and the page: the section title (links to its overview) and children.
  def section_nav(basename)
    sec = section_for(basename)
    return '' unless sec

    title_cls = sec['page'] == basename ? 'subnav-title active' : 'subnav-title'
    title_cur = sec['page'] == basename ? ' aria-current="page"' : ''
    items = sec['children'].map do |c|
      active = c['page'] == basename
      cls = active ? 'nav-link active' : 'nav-link'
      cur = active ? ' aria-current="page"' : ''
      %(    <li class="nav-item"><a class="#{cls}"#{cur} href="#{c['page']}">#{CGI.escapeHTML(c['title'])}</a></li>\n)
    end
    label = CGI.escapeHTML(sec['title'])
    %(<nav class="subnav" aria-label="#{label} section">\n  <a class="#{title_cls}"#{title_cur} href="#{sec['page']}">#{label}</a>\n  <ul class="nav">\n#{items.join}  </ul>\n</nav>\n)
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
        body = { 'breadcrumb' => breadcrumb(basename), 'section-nav' => section_nav(basename), 'social' => social_links(:list) }.fetch(name)
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
