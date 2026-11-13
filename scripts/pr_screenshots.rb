#!/usr/bin/env ruby
# frozen_string_literal: true

# Before/after screenshot tables for page-change PRs (desktop and mobile), like the baseline PR.
#
#   1. Capture (see README): RUN_VISUAL=1 CAPTURE_LABEL=<label> bundle exec rspec spec/visual/pages_spec.rb
#   2. Stage the PNGs for the pages a PR changes into docs/screenshots/<name>/ (Netlify never serves docs/):
#        ruby scripts/pr_screenshots.rb stage --name pr-22-nav --pages foray_2024,foray_2026 \
#             --before tmp/visual/pr21 --after tmp/visual/after-nav
#      A --before directory that is already under docs/screenshots/ (e.g. the committed baseline) is referenced
#      in place instead of copied.
#   3. Commit and push, then print the markdown for the PR body with URLs pinned to commit SHAs:
#        ruby scripts/pr_screenshots.rb table --name pr-22-nav --sha <commit with the images> [--before-sha <sha>]
require 'json'
require 'fileutils'
require 'optparse'

ROOT = File.expand_path('..', __dir__)
SHOTS = File.join(ROOT, 'docs', 'screenshots')
DEVICES = %w[desktop mobile].freeze
WIDTHS = { 'desktop' => 420, 'mobile' => 210 }.freeze

def opts(argv)
  o = {}
  OptionParser.new do |p|
    p.on('--name N') { |v| o[:name] = v }
    p.on('--pages P') { |v| o[:pages] = v.split(',') }
    p.on('--before D') { |v| o[:before] = File.expand_path(v, ROOT) }
    p.on('--after D') { |v| o[:after] = File.expand_path(v, ROOT) }
    p.on('--sha S') { |v| o[:sha] = v }
    p.on('--before-sha S') { |v| o[:before_sha] = v }
    p.on('--repo R') { |v| o[:repo] = v }
  end.parse!(argv)
  o
end

def rel(path) = path.sub("#{ROOT}/", '')

def stage(o)
  abort 'need --name, --pages, --before, --after' unless o.values_at(:name, :pages, :before, :after).all?
  dest = File.join(SHOTS, o[:name])
  committed_before = o[:before].start_with?("#{SHOTS}/")
  before_base = committed_before ? rel(o[:before]) : File.join('docs', 'screenshots', o[:name], 'before')
  after_base = File.join('docs', 'screenshots', o[:name], 'after')
  o[:pages].each do |page|
    DEVICES.each do |device|
      copy = lambda do |from, base|
        src = File.join(from, device, "#{page}.png")
        abort "missing #{rel(src)}" unless File.exist?(src)
        out = File.join(ROOT, base, device, "#{page}.png")
        FileUtils.mkdir_p(File.dirname(out))
        FileUtils.cp(src, out)
      end
      copy.call(o[:before], before_base) unless committed_before
      copy.call(o[:after], after_base)
    end
  end
  FileUtils.mkdir_p(dest)
  File.write(File.join(dest, 'manifest.json'),
             JSON.pretty_generate(pages: o[:pages], before_base:, after_base:) + "\n")
  puts "Staged #{o[:pages].size} page(s) in #{rel(dest)} (before: #{before_base})"
end

def repo_slug(o)
  return o[:repo] if o[:repo]

  url = `git -C #{ROOT} remote get-url origin`.strip
  url[%r{github\.com[:/](.+?)(?:\.git)?\z}, 1] || abort('pass --repo OWNER/REPO')
end

def table(o)
  abort 'need --name and --sha' unless o[:name] && o[:sha]
  manifest = JSON.parse(File.read(File.join(SHOTS, o[:name], 'manifest.json')))
  repo = repo_slug(o)
  url = lambda do |sha, base, device, page|
    "https://github.com/#{repo}/blob/#{sha}/#{base}/#{device}/#{page}.png?raw=true"
  end
  img = lambda do |sha, base, device, page, label|
    %(<img src="#{url.call(sha, base, device, page)}" alt="#{page} #{label} #{device}" width="#{WIDTHS[device]}">)
  end
  manifest['pages'].each do |page|
    puts "**#{page}**", '', '| | Desktop | Mobile |', '|---|---|---|'
    puts "| Before | #{DEVICES.map { |d| img.call(o[:before_sha] || o[:sha], manifest['before_base'], d, page, 'before') }.join(' | ')} |"
    puts "| After | #{DEVICES.map { |d| img.call(o[:sha], manifest['after_base'], d, page, 'after') }.join(' | ')} |"
    puts
  end
end

command = ARGV.shift
o = opts(ARGV)
case command
when 'stage' then stage(o)
when 'table' then table(o)
else abort 'usage: pr_screenshots.rb stage|table (see header comment)'
end
