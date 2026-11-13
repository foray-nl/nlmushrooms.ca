require "spec_helper"
require_relative "../scripts/apply_layout"

RSpec.describe "Site footer" do
  let(:root) { ApplyLayout::ROOT }
  let(:html) { ApplyLayout.footer("index.html") }
  let(:hrefs) { html.scan(/<a href="([^"#]+\.html)"/).flatten.uniq }
  let(:config) { ApplyLayout.footer_config }

  it "links only to registered pages that exist" do
    hrefs.each do |h|
      expect(ApplyLayout.entry(h)).not_to be_nil, "#{h} is not in the page registry"
      expect(File).to exist(File.join(root, h))
    end
  end

  it "covers every top-level nav destination except Home and About Us" do
    nav = File.read(File.join(root, "layout/partials/nav.html"), encoding: "UTF-8")
    top = nav.scan(/<li class="nav-item">\s*<a [^>]*href="([^"]+)"/).flatten +
          nav.scan(/<li class="nav-item dropdown">.*?<a class="dropdown-item" href="([^"]+)"/m).flatten
    expect(top - hrefs - %w[index.html about_us.html]).to be_empty
  end

  it "keeps the next-foray line hidden until the script has compared dates" do
    line = html[/<p class="footer-next-foray"[^>]*>/]
    expect(line).to include("hidden").and match(/data-start="\d{4}-\d{2}-\d{2}"/).and match(/data-end="\d{4}-\d{2}-\d{2}"/)
  end

  it "has a back-to-top link everywhere except the 404 page, which resolves links from the site root" do
    expect(html).to include('href="#page-top"')
    expect(ApplyLayout.footer("404.html")).not_to include("#page-top")
  end

  it "does not publish an email address or street address" do
    expect(html).not_to match(/@|mailto:|Brown/)
  end

  it "links to the privacy and accessibility pages" do
    expect(config["legal"]).to include("privacy.html", "accessibility.html")
  end
end
