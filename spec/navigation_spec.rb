require "spec_helper"

RSpec.describe "Site navigation", type: :feature do
  NAV_LINKS = {
    "Home" => "index.html",
    "Foray 2025" => "foray_2025.html",
    "Foray Reports" => "foray_reports.html",
    "Species List Explanations" => "species_list_explanations.html",
    "Omphalina" => "omphalina.html",
    "Science" => "science.html",
    "Resources" => "resources.html",
    "About Us" => "about_us.html",
    "Membership" => "membership.html"
  }.freeze

  NAV_LINKS.each do |text, path|
    it "navigates to #{path} and finds heading and content" do
      visit "/index.html"
      within("#main-nav") do
        click_link text
      end
      expect(page).to have_current_path("/#{path}")
      expect(page.title).not_to be_empty
      expect(page).to have_css("p", minimum: 1)
    end
  end
end
