#!/usr/bin/env ruby
# frozen_string_literal: true

# Reads tmp/visual/before and tmp/visual/after (see spec/visual/pages_spec.rb) and writes
#   tmp/visual/compare/index.html   before | after contact sheet, desktop and mobile
#   tmp/visual/axe-summary.md       axe violations per page, before vs after (commit this one)
# Read-only with respect to the site: it never touches page files.
require 'cgi'
require 'fileutils'
require 'json'

root = File.expand_path('../tmp/visual', __dir__)
before = JSON.parse(File.read(File.join(root, 'before', 'axe.json')))
after_file = File.join(root, 'after', 'axe.json')
after = File.exist?(after_file) ? JSON.parse(File.read(after_file)) : {}

count = ->(entry, impacts) { entry ? entry['violations'].select { |v| impacts.include?(v['impact']) }.sum { |v| v['nodes'] } : nil }
cell = ->(n) { n.nil? ? 'n/a' : n.to_s }
slug = ->(path) { path.sub(/\.html\z/, '').gsub(%r{[^A-Za-z0-9]+}, '_').gsub(/\A_|_\z/, '').downcase }

lines = ['# axe-core before vs after (nodes)', '',
         '| Page | crit/serious before | crit/serious after | all before | all after | broken imgs after |',
         '|---|---:|---:|---:|---:|---:|']
(before.keys | after.keys).sort.each do |path|
  b = before[path]
  a = after[path]
  worse = a && b && count.call(a, %w[critical serious]) > count.call(b, %w[critical serious])
  lines << "| #{path}#{' **(worse)**' if worse} | #{cell.call(count.call(b, %w[critical serious]))} | " \
           "#{cell.call(count.call(a, %w[critical serious]))} | #{cell.call(count.call(b, %w[critical serious minor moderate]))} | " \
           "#{cell.call(count.call(a, %w[critical serious minor moderate]))} | #{a ? a['broken_images'].size : 'n/a'} |"
end
File.write(File.join(root, 'axe-summary.md'), "#{lines.join("\n")}\n")

html = +"<!doctype html><meta charset=utf-8><title>Before/after</title><style>body{font:14px sans-serif}" \
        "table{border-collapse:collapse}td{vertical-align:top;border:1px solid #ccc;padding:4px}img{max-width:420px}</style>" \
        "<h1>Before | After</h1><table>"
before.keys.sort.each do |path|
  html << "<tr><td colspan=4><b>#{CGI.escapeHTML(path)}</b></td></tr><tr>"
  %w[desktop mobile].each do |device|
    %w[before after].each do |label|
      file = "../#{label}/#{device}/#{slug.call(path)}.png"
      exists = File.exist?(File.join(root, 'compare', file))
      html << "<td>#{label} #{device}<br>#{exists ? "<img src=\"#{file}\" loading=lazy>" : '(not captured)'}</td>"
    end
  end
  html << '</tr>'
end
FileUtils.mkdir_p(File.join(root, 'compare'))
File.write(File.join(root, 'compare', 'index.html'), "#{html}</table>")
puts "wrote #{File.join(root, 'axe-summary.md')} and compare/index.html"
