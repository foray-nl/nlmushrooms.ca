# frozen_string_literal: true

require 'capybara/rspec'
require 'selenium-webdriver'
require 'tmpdir'


# Headless Chrome, same shape as the community-engine-rails / NLO drivers.
# Selenium Manager downloads Chrome and chromedriver when they are not installed.
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  %w[--headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage --window-size=1440,1600].each do |arg|
    options.add_argument(arg)
  end
  options.add_argument("--user-data-dir=#{Dir.mktmpdir("chrome-#{Process.pid}-")}")

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options:,
    http_client: Selenium::WebDriver::Remote::Http::Default.new(
      read_timeout: Integer(ENV.fetch('SELENIUM_READ_TIMEOUT', 45))
    )
  )
end

Capybara.javascript_driver = :selenium_chrome_headless
Capybara.server = :puma, { Silent: true }
Capybara.server_host = '127.0.0.1'
Capybara.always_include_port = true
