# frozen_string_literal: true

# Writes sitemap.xml: every public HTML page and PDF, one <loc> per canonical URL (registered pages use the canonical
# URL from layout/site-nav.yml, so the home page is https://nlmushrooms.ca/). No images, styles or scripts, no 404
# page, nothing from tooling directories. lastmod is left out on purpose: the repository cannot tell a content change
# from a re-save, and a wrong lastmod is worse than none.
#
#   ruby sitemap.rb
require 'builder'
require 'uri'
require_relative 'scripts/apply_layout'

module Sitemap
  ROOT = ApplyLayout::ROOT
  EXCLUDE = %r{\A(?:tmp|docs|archive|layout|vendor|spec|scripts|manifests|assets|node_modules)/|\A404\.html\z}

  module_function

  def files
    Dir.chdir(ROOT) { Dir.glob('**/*.{html,pdf}').reject { |f| f.match?(EXCLUDE) }.sort }
  end

  def url(file)
    return ApplyLayout.canonical_url(file) if ApplyLayout.entry(file)

    "#{ApplyLayout.site['url']}/#{URI::DEFAULT_PARSER.escape(file)}"
  end

  def urls
    files.map { |f| url(f) }.sort
  end

  def xml
    builder = Builder::XmlMarkup.new(indent: 2)
    builder.instruct! :xml, version: '1.0', encoding: 'UTF-8'
    builder.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') do
      urls.each { |u| builder.url { builder.loc(u) } }
    end
    builder.target!
  end
end

if $PROGRAM_NAME == __FILE__
  File.write(File.join(Sitemap::ROOT, 'sitemap.xml'), "#{Sitemap.xml}\n")
  puts "sitemap.xml: #{Sitemap.urls.size} URLs"
end
