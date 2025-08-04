require "spec_helper"

RSpec.describe "Site navigation", type: :feature do
  NAV_LINKS = {
    nav_4_B1: "index.html",
    nav_4_B2: "foray_2025.html",
    nav_4_B3: "foray_reports.html",
    nav_4_B4: "species_list_explanations.html",
    nav_4_B5: "omphalina.html",
    nav_4_B6: "science.html",
    nav_4_B7: "resources.html",
    nav_4_B8: "about_us.html",
    nav_4_B9: "membership.html"
  }.freeze

  NAV_LINKS.each do |id, path|
    it "navigates to #{path} and finds heading and content" do
      visit "/index.html"
      find("##{id}").click
      expect(page).to have_current_path("/#{path}")
      expect(page.title).not_to be_empty
      expect(page).to have_css("p", minimum: 1)
    end
  end
end
