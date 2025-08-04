require 'nokogiri'
require 'set'
require 'pathname'

ROOT = Pathname.new(File.expand_path('.', __dir__))

visited = Set.new
assets = Set.new


def crawl(path, depth, visited, assets)
  return if depth < 0 || visited.include?(path)
  visited << path
  full_path = ROOT.join(path)
  return unless full_path.file?
  doc = Nokogiri::HTML(full_path.read)
  doc.css('a[href], img[src]').each do |node|
    link = node['href'] || node['src']
    next if link.nil? || link.start_with?('#', 'mailto:', 'http', 'https')
    normalized = ROOT.join(path).dirname.join(link).cleanpath.relative_path_from(ROOT).to_s
    if normalized.match?(/\.html?$/i)
      crawl(normalized, depth - 1, visited, assets)
    else
      assets << normalized
    end
  end
end

crawl('index.html', 2, visited, assets)

File.open('sitemap.txt', 'w') do |f|
  f.puts 'HTML Pages:'
  visited.sort.each { |p| f.puts p }
  f.puts
  f.puts 'Assets:'
  assets.sort.each { |a| f.puts a }
end
