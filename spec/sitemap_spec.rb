require 'spec_helper'
require 'nokogiri'
require_relative '../sitemap'

RSpec.describe 'Sitemap and robots.txt' do
  let(:committed) { Nokogiri::XML(File.read('sitemap.xml')).xpath('//xmlns:loc').map(&:text) }

  it 'is up to date with the pages and PDFs in the repository' do
    expect(committed).to eq(Sitemap.urls), 'run `ruby sitemap.rb`'
  end

  it 'lists the canonical URL of every registered page, with the home page as the bare domain' do
    ApplyLayout.registry.each { |p| expect(committed).to include(ApplyLayout.canonical_url(p['file'])) }
    expect(committed).to include('https://nlmushrooms.ca/')
    expect(committed).not_to include('https://nlmushrooms.ca/index.html')
  end

  it 'lists only pages and PDFs that exist, never the 404 page, images, styles or tooling' do
    expect(committed).to all(match(%r{\Ahttps://nlmushrooms\.ca/(?:|.*\.(?:html|pdf))\z}))
    expect(committed).not_to include('https://nlmushrooms.ca/404.html')
    committed.each do |u|
      file = URI.decode_www_form_component(u.sub('https://nlmushrooms.ca/', '').then { |f| f.empty? ? 'index.html' : f })
      expect(File).to exist(file), "#{u} has no file"
    end
  end

  it 'points robots.txt at the sitemap and blocks only the archive' do
    robots = File.read('robots.txt')
    expect(robots).to include('Sitemap: https://nlmushrooms.ca/sitemap.xml')
    expect(robots.scan(/^Disallow:\s*(\S+)/).flatten).to eq(['/archive/'])
  end

  it 'keeps the 404 page out of search results' do
    expect(File.read('404.html')).to include('<meta name="robots" content="noindex">')
  end
end
