# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'cgi'
require 'base64'

# Before/after page captures: desktop and mobile PNGs plus axe-core results per page.
# Ported from NLO's DocsScreenshots helper (no Rails, no vips). Output goes to tmp/visual/<label>/.
#
#   SITE_ROOT   directory to serve (default: repo root; the baseline is a worktree of the baseline commit)
#   CAPTURE_LABEL  before | after (default: after)
module PageCapture
  DEVICES = { desktop: [1440, 900], mobile: [430, 900] }.freeze
  REPO_ROOT = File.expand_path('../..', __dir__)
  # Drop analytics and fonts so captures are deterministic and offline-safe; the page keeps its tag.
  BLOCKED_HOSTS = %w[googletagmanager.com google-analytics.com fonts.googleapis.com fonts.gstatic.com].freeze

  module_function

  def site_root = File.expand_path(ENV.fetch('SITE_ROOT', REPO_ROOT))
  def label = ENV.fetch('CAPTURE_LABEL', 'after')
  def out_dir = File.join(REPO_ROOT, 'tmp', 'visual', label)

  # Every HTML page on disk (sitemap.xml is known to be incomplete), as paths relative to the site root.
  def pages
    Dir.chdir(site_root) { Dir.glob('**/*.html').reject { |f| f.start_with?('tmp/', 'vendor/', 'layout/') }.sort }
  end

  def slug(path) = path.sub(/\.html\z/, '').gsub(%r{[^A-Za-z0-9]+}, '_').gsub(/\A_|_\z/, '').downcase

  def block_trackers(page)
    page.driver.browser.execute_cdp('Network.enable')
    page.driver.browser.execute_cdp('Network.setBlockedURLs', urls: BLOCKED_HOSTS.map { |h| "*#{h}*" })
  end

  # Full-page screenshot per device via CDP. Mobile uses device emulation so the page's viewport meta is honoured
  # (the legacy pages declare width=1024, which is exactly what a phone would show).
  def capture(page, path)
    browser = page.driver.browser
    block_trackers(page)
    DEVICES.each do |device, (width, height)|
      browser.execute_cdp('Emulation.setDeviceMetricsOverride',
                          width:, height:, deviceScaleFactor: 1, mobile: device == :mobile)
      page.visit("/#{path.split('/').map { |s| CGI.escape(s).gsub('+', '%20') }.join('/')}")
      wait_for_images(page)
      size = page.evaluate_script('[document.documentElement.scrollWidth, Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)]')
      shot = browser.execute_cdp('Page.captureScreenshot', format: 'png', captureBeyondViewport: true,
                                 clip: { x: 0, y: 0, width: [size[0], width].max, height: size[1], scale: 1 })
      file = File.join(out_dir, device.to_s, "#{slug(path)}.png")
      FileUtils.mkdir_p(File.dirname(file))
      File.binwrite(file, Base64.decode64(shot['data']))
    end
  end

  def wait_for_images(page)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until page.evaluate_script('Array.from(document.images).every(function (i) { return i.complete })')
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  def broken_images(page)
    page.evaluate_script(<<~JS)
      Array.from(document.images).filter(function (i) { return i.complete && i.naturalWidth === 0 })
        .map(function (i) { return i.getAttribute('src') })
    JS
  end

  def record_axe(path, results, broken_imgs)
    FileUtils.mkdir_p(out_dir)
    file = File.join(out_dir, 'axe.json')
    data = File.exist?(file) ? JSON.parse(File.read(file)) : {}
    data[path] = {
      'violations' => results.violations.map do |v|
        { 'id' => v.id, 'impact' => v.impact, 'nodes' => v.nodes.size, 'targets' => v.nodes.map { |n| n.target.to_s }.first(5) }
      end,
      'broken_images' => broken_imgs
    }
    File.write(file, JSON.pretty_generate(data))
  end
end
