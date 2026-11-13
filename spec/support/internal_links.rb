# frozen_string_literal: true

require 'nokogiri'
require 'uri'
require 'cgi'

# Read-only scan of every internal reference (a, area, img, link, script, iframe, source, form) in the site's
# HTML pages. Resolves each against the page's own directory, decodes %20, drops query and fragment, and reports
# targets that do not exist on disk. Used by the missing-files manifest spec; never edits any file.
module InternalLinks
  ROOT = File.expand_path('../..', __dir__)
  ATTRS = { 'a' => 'href', 'area' => 'href', 'img' => 'src', 'link' => 'href', 'script' => 'src',
            'iframe' => 'src', 'source' => 'src', 'form' => 'action' }.freeze
  EXTERNAL = %r{\A(?:[a-z][a-z0-9+.-]*:|//)}i
  SKIP_DIRS = %w[tmp/ vendor/ docs/ node_modules/].freeze

  module_function

  def pages
    Dir.chdir(ROOT) { Dir.glob('**/*.html').reject { |f| SKIP_DIRS.any? { |d| f.start_with?(d) } }.sort }
  end

  # { 'missing/path.pdf' => ['referring_page.html', ...] }, optionally ignoring pages slated for removal.
  def missing(ignore_sources: [])
    found = Hash.new { |h, k| h[k] = [] }
    (pages - ignore_sources).each do |page|
      doc = Nokogiri::HTML(File.read(File.join(ROOT, page), encoding: 'UTF-8'))
      ATTRS.each do |tag, attr|
        doc.css("#{tag}[#{attr}]").each do |node|
          target = resolve(page, node[attr])
          found[target] << page if target && !File.exist?(File.join(ROOT, target))
        end
      end
    end
    found.transform_values { |sources| sources.uniq.sort }.sort.to_h
  end

  def resolve(page, ref)
    ref = ref.to_s.strip
    return nil if ref.empty? || ref.start_with?('#') || ref.match?(EXTERNAL)

    path = CGI.unescape(ref.sub(/[?#].*\z/, '').gsub('+', '%2B'))
    return nil if path.empty?

    base = path.start_with?('/') ? '' : File.dirname(page)
    File.expand_path(path, File.join('/', base)).sub(%r{\A/}, '').sub(%r{/\z}, '')
  end
end
