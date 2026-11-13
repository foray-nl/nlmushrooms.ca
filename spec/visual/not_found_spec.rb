# frozen_string_literal: true

require 'support/capybara'
require 'support/page_capture'
require 'rack/files'

# One screenshot pair per 404 headline, forced with ?headline=N so the captures are repeatable.
#
#   RUN_VISUAL=1 CAPTURE_LABEL=404 bundle exec rspec spec/visual/not_found_spec.rb
RSpec.describe '404 headlines', :js, type: :feature do
  before(:all) { skip 'set RUN_VISUAL=1 to capture screenshots' unless ENV['RUN_VISUAL'] }

  around do |example|
    previous = Capybara.app
    Capybara.app = PageCapture.app
    example.run
  ensure
    Capybara.app = previous
  end

  (1..4).each do |n|
    it "captures headline #{n}" do
      PageCapture.capture(page, '404.html', query: "headline=#{n}", name: "404_headline_#{n}")
      shown = page.all('[data-line]', visible: :visible)
      expect(shown.size).to eq(1)
      expect(page).to have_css('h1', count: 1)
    end
  end
end
