# frozen_string_literal: true

require 'support/capybara'
require 'support/page_capture'
require 'rack/files'

# Behaviour of the shared nav (Bootstrap navbar-expand-lg + collapse) in a real browser. Opt-in like the page captures:
#
#   RUN_VISUAL=1 bundle exec rspec spec/visual/nav_spec.rb
#
# Viewport screenshots of the collapsed and expanded mobile nav go to tmp/visual/<label>/.
RSpec.describe 'Main navigation', :js, type: :feature do
  PAGES = %w[foray_2026.html foray_2024.html].freeze

  before(:all) { skip 'set RUN_VISUAL=1 to run browser specs' unless ENV['RUN_VISUAL'] }

  around do |example|
    previous = Capybara.app
    Capybara.app = PageCapture.app
    example.run
  ensure
    Capybara.app = previous
  end

  def resize(width, mobile: false)
    page.driver.browser.execute_cdp('Emulation.setDeviceMetricsOverride',
                                    width:, height: 900, deviceScaleFactor: 1, mobile:)
  end

  def visit_page(path)
    PageCapture.block_trackers(page)
    visit("/#{path}")
  end

  def overflow?
    page.evaluate_script('document.documentElement.scrollWidth > document.documentElement.clientWidth')
  end

  def shot(name)
    FileUtils.mkdir_p(PageCapture.out_dir)
    page.driver.browser.save_screenshot(File.join(PageCapture.out_dir, "nav-#{name}.png"))
  end

  PAGES.each do |path|
    context "on #{path}" do
      it 'collapses behind a toggler on a phone and opens and closes it' do
        resize(430, mobile: true)
        visit_page(path)
        expect(page).to have_css('.navbar-toggler', visible: :visible)
        expect(page).to have_no_link('Membership')
        expect(page).to have_css('.navbar-toggler[aria-expanded="false"]')
        shot("#{PageCapture.slug(path)}-mobile-collapsed")

        find('.navbar-toggler').click
        expect(page).to have_link('Membership')
        expect(page).to have_css('.navbar-toggler[aria-expanded="true"]')
        expect(page).to have_css('#siteNav.collapse.show:not(.collapsing)') # Bootstrap ignores clicks mid-transition
        shot("#{PageCapture.slug(path)}-mobile-expanded")

        find('.navbar-toggler').click
        expect(page).to have_no_link('Membership')
      end

      it 'does not scroll sideways on a phone, collapsed or expanded' do
        resize(430, mobile: true)
        visit_page(path)
        expect(overflow?).to be(false)
        find('.navbar-toggler').click
        expect(page).to have_link('Membership')
        expect(overflow?).to be(false)
      end

      it 'opens a dropdown on a phone and lists the sub-pages' do
        resize(430, mobile: true)
        visit_page(path)
        find('.navbar-toggler').click
        expect(page).to have_css('#siteNav.collapse.show:not(.collapsing)')
        click_button 'Omphalina'
        expect(page).to have_css('button.dropdown-toggle[aria-expanded="true"]')
        expect(page).to have_link('Vol 1, 2010')
        expect(page).to have_link('Submission Guidelines')
        expect(overflow?).to be(false)
        shot("#{PageCapture.slug(path)}-mobile-dropdown")
      end

      it 'opens a dropdown on a desktop and closes it on a second click' do
        resize(1440)
        visit_page(path)
        click_button 'Species List'
        expect(page).to have_link('Flickr Images')
        shot("#{PageCapture.slug(path)}-desktop-dropdown")
        click_button 'Species List'
        expect(page).to have_no_link('Flickr Images')
      end

      it 'shows all nine links on one row without a toggler from 992 px up' do
        [992, 1200, 1440].each do |width|
          resize(width)
          visit_page(path)
          expect(page).to have_no_css('.navbar-toggler', visible: :visible)
          tops = page.evaluate_script("Array.from(document.querySelectorAll('.navbar-nav > .nav-item > .nav-link')).map(function (a) { return Math.round(a.getBoundingClientRect().top) })")
          expect(tops.size).to eq(9)
          expect(tops.uniq.size).to eq(1), "links wrapped at #{width}px: #{tops.inspect}"
          expect(overflow?).to be(false), "page scrolls sideways at #{width}px"
        end
      end
    end
  end

  describe 'social icons in the header' do
    {
      'Facebook: ForayNL' => 'https://www.facebook.com/ForayNL',
      'Instagram: @foraynl' => 'https://www.instagram.com/foraynl/',
      'Flickr: foray_nl' => 'https://www.flickr.com/photos/foray_nl/'
    }.each do |label, url|
      it "names #{label} in a tooltip on hover and on keyboard focus" do
        resize(1440)
        visit_page('about_us.html')
        link = find("a.social-link[href='#{url}']")
        expect(link['aria-label']).to eq("#{label} (opens in a new tab)")
        link.hover
        expect(page).to have_css('.tooltip.show .tooltip-inner', text: label)
        page.execute_script('document.activeElement && document.activeElement.blur()')
        page.driver.browser.action.move_to_location(5, 5).perform
        expect(page).to have_no_css('.tooltip.show')
        page.execute_script("document.querySelector(\"a.social-link[href='#{url}']\").focus()")
        expect(page).to have_css('.tooltip.show .tooltip-inner', text: label)
      end
    end

    it 'stays inside the viewport on a phone and on a wide desktop' do
      [[430, true], [1440, false]].each do |width, mobile|
        resize(width, mobile:)
        visit_page('about_us.html')
        expect(page).to have_css('a.social-link', count: 3)
        expect(overflow?).to be(false)
        shot("social-#{width}")
      end
    end
  end
end
