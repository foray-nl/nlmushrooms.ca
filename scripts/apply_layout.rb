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
# Regions: head (shared <link>s), header, nav, footer. Everything outside the markers is left alone.
# In the nav region the link to the page being written gets class="... active" and aria-current="page" (and so does its dropdown toggle).
#
#   ruby scripts/apply_layout.rb            rewrite every page that has markers
#   ruby scripts/apply_layout.rb --check    exit 1 and list pages that differ (CI drift check); writes nothing
#   ruby scripts/apply_layout.rb a.html     only the named pages
module ApplyLayout
  ROOT = File.expand_path('..', __dir__)
  PARTIALS = File.join(ROOT, 'layout', 'partials')
  REGIONS = %w[head header nav footer].freeze

  module_function

  def pages
    Dir.glob(File.join(ROOT, '**', '*.html')).reject { |f| f.sub("#{ROOT}/", '').start_with?('tmp/', 'vendor/', 'layout/') }.sort
  end

  def partial(name)
    File.read(File.join(PARTIALS, "#{name}.html"), encoding: 'UTF-8')
  end

  def render(source, page_path)
    REGIONS.reduce(source) do |text, name|
      text.gsub(region_pattern(name)) do
        indent = Regexp.last_match(1)
        body = partial(name)
        body = mark_active(body, File.basename(page_path)) if name == 'nav'
        lines = body.lines.map { |l| l.strip.empty? ? l : "#{indent}#{l}" }.join
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
