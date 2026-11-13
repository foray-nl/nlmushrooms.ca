require "spec_helper"
require "yaml"

# Files under archive/ stay in the repository but must never be served, listed or linked.
RSpec.describe "archive directory" do
  root = File.expand_path("..", __dir__)

  it "is blocked by a forced 404 redirect in netlify.toml" do
    toml = File.read(File.join(root, "netlify.toml"))
    expect(toml).to match(%r{from = "/archive/\*"\s+to = "/404.html"\s+status = 404\s+force = true})
  end

  it "is disallowed in robots.txt and absent from the sitemap" do
    expect(File.read(File.join(root, "robots.txt"))).to include("Disallow: /archive/")
    expect(File.read(File.join(root, "sitemap.xml"))).not_to include("/archive/")
  end

  it "is not linked from any page or data file" do
    sources = Dir.glob(File.join(root, "{*.html,layout/*.yml}"))
    linked = sources.select { |f| File.read(f, encoding: "UTF-8").include?("archive/") }
    expect(linked).to be_empty
  end
end
