# frozen_string_literal: true

require 'axe-capybara'
require 'axe-rspec'

# axe samples colours at call time, so a running CSS transition gives blended values and flaky contrast
# failures. Disable motion and wait for running animations before every audit (from community-engine-rails).
module AxeMotionSettle
  DISABLE_MOTION_JS = <<~JS
    if (!document.getElementById('axe-no-motion')) {
      var style = document.createElement('style');
      style.id = 'axe-no-motion';
      style.textContent = '*, *::before, *::after { transition: none !important; animation: none !important; }';
      document.head.appendChild(style);
    }
  JS

  def self.settle(page)
    page.execute_script(DISABLE_MOTION_JS)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while page.evaluate_script('document.getAnimations().length').to_i.positive?
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  rescue Capybara::NotSupportedByDriverError
    nil
  end
end

# Same hook as community-engine-rails: settle motion before every be_axe_clean audit.
module AxeMotionSettleMatcher
  def audit(page)
    AxeMotionSettle.settle(page) unless @audit
    super
  end
end
Axe::Matchers::BeAxeClean.prepend(AxeMotionSettleMatcher)
