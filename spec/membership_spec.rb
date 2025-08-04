require "spec_helper"

RSpec.describe "Membership page", type: :feature do
  it "links to the membership form PDF" do
    visit "/membership.html"
    link = find("a[href='/forms/ForayNL_MembershipForm_2024-01.pdf']")
    visit link[:href]
    expect(page.status_code).to eq 200
  end
end
