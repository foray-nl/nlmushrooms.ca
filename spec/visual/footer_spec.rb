# frozen_string_literal: true

require 'support/capybara'
require 'support/page_capture'
require 'rack/files'

# Footer in both states of the "Next foray" line, forced with ?today= so the captures are repeatable.
#
#   RUN_VISUAL=1 CAPTURE_LABEL=footer bundle exec rspec spec/visual/footer_spec.rb
RSpec.describe 'Footer states', :js, type: :feature do
  before(:all) { skip 'set RUN_VISUAL=1 to capture screenshots' unless ENV['RUN_VISUAL'] }

  around do |example|
    previous = Capybara.app
    Capybara.app = PageCapture.app
    example.run
  ensure
    Capybara.app = previous
  end

  {
    'footer_next_foray_shown' => ['today=2026-09-01', true],
    'footer_no_upcoming_foray' => ['today=2026-11-13', false]
  }.each do |name, (query, shown)|
    it "captures #{name}" do
      PageCapture.capture(page, 'index.html', query:, name:)
      expect(page).to have_css('.footer-next-foray', visible: shown ? :visible : :hidden)
    end
  end
end
