# frozen_string_literal: true

require 'support/capybara'
require 'support/axe'
require 'support/page_capture'
require 'rack/files'

# Screenshots (desktop and mobile) and axe-core results for every page. Needs Chrome, so it is opt-in:
#
#   RUN_VISUAL=1 bundle exec rspec spec/visual/pages_spec.rb
#   RUN_VISUAL=1 SITE_ROOT=tmp/baseline CAPTURE_LABEL=before bundle exec rspec spec/visual/pages_spec.rb
#
# Results are reports only (violations recorded in tmp/visual/<label>/axe.json); ruby scripts/compare_visual.rb
# turns before vs after into a contact sheet and a table.
RSpec.describe 'Page screenshots and accessibility', :js, type: :feature do
  before(:all) do
    skip 'set RUN_VISUAL=1 to capture screenshots and axe results' unless ENV['RUN_VISUAL']
    FileUtils.rm_rf(PageCapture.out_dir)
  end

  around do |example|
    previous = Capybara.app
    Capybara.app = Rack::Files.new(PageCapture.site_root)
    example.run
  ensure
    Capybara.app = previous
  end

  PageCapture.pages.each do |path|
    it "captures #{path}" do
      PageCapture.capture(page, path)
      PageCapture.record_axe(path, Axe::Matchers::BeAxeClean.new.audit(page).results, PageCapture.broken_images(page))
    end
  end
end
