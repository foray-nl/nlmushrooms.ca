#!/usr/bin/env ruby
require 'nokogiri'

NAV_PATH = File.join(File.dirname(__dir__), 'navigation.html')
NAV_HTML = File.read(NAV_PATH)

Dir.glob(File.join(File.dirname(__dir__), '**/*.html')).each do |file|
  next if File.basename(file) == 'navigation.html'
  doc = Nokogiri::HTML(File.read(file))
  # remove old nav and related dropdown menus
  doc.css('#nav_4').remove
  doc.css('[id^="nav_4_B"]').remove
  # remove scripts for old menu
  doc.xpath("//script[contains(., 'wpmenustack')]").remove
  doc.xpath("//script[contains(., 'ActiveButton')]").remove
  doc.at_css('script[src*="jquery.js"]')&.remove
  # remove any existing main-nav
  doc.css('#main-nav').remove
  # insert new nav at top of body
  if body = doc.at('body')
    body.children.first.add_previous_sibling(Nokogiri::HTML::DocumentFragment.parse(NAV_HTML))
    body.add_child('<script src="/_wp_scripts/navigation.js"></script>')
    File.write(file, doc.to_html)
    puts "Updated #{file}"
  else
    warn "No body tag in #{file}"
  end
end
