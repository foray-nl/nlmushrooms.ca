require "spec_helper"
require "nokogiri"

RSpec.describe "Sitemap", type: :feature do
  it "includes header navigation pages" do
    xml = Nokogiri::XML(File.read("sitemap.xml"))
    urls = xml.xpath("//xmlns:loc").map(&:text)
    expected = %w[
      https://nlmushrooms.ca/index.html
      https://nlmushrooms.ca/foray_2025.html
      https://nlmushrooms.ca/foray_reports.html
      https://nlmushrooms.ca/species_list_explanations.html
      https://nlmushrooms.ca/omphalina.html
      https://nlmushrooms.ca/science.html
      https://nlmushrooms.ca/resources.html
      https://nlmushrooms.ca/about_us.html
      https://nlmushrooms.ca/membership.html
    ]
    expected.each do |url|
      expect(urls).to include(url)
    end
  end
end
