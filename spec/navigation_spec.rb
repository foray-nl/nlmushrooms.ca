require "spec_helper"

RSpec.describe "Site navigation", type: :feature do
  NAV_LINKS = %w[
    index.html
    foray_2026.html
    foray_reports.html
    species_list_explanations.html
    omphalina.html
    science.html
    resources.html
    about_us.html
    membership.html
  ].freeze

  NAV_LINKS.each do |path|
    it "navigates to #{path} and finds heading and content" do
      visit "/index.html"
      within("nav") { click_link href: path }
      expect(page).to have_current_path("/#{path}")
      expect(page.title).not_to be_empty
      expect(page).to have_css("p", minimum: 1)
    end
  end
end
