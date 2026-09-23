require "capybara/playwright"

# End-to-end specs drive a real Chromium through Playwright. The browser comes from the
# `playwright` npm package in node_modules, which must stay on the version
# playwright-ruby-client expects (Playwright::COMPATIBLE_PLAYWRIGHT_VERSION); a mismatch
# fails at launch rather than halfway through a spec. Install the browser once with
# `npx playwright install chromium`.
#
# Headless by default. HEADED=1 opens a visible window, slowed down enough to follow:
#   HEADED=1 bundle exec rspec spec/system
VIEWPORTS = { desktop: { width: 1280, height: 900 }, phone: { width: 375, height: 812 } }.freeze
COLOR_SCHEMES = %i[light dark].freeze

# One driver per viewport and system colour scheme, named playwright_<viewport>_<scheme>.
# The scheme is what the operating system reports, which is what the app follows until
# the student picks a theme themselves.
VIEWPORTS.each do |name, viewport|
  COLOR_SCHEMES.each do |scheme|
    Capybara.register_driver(:"playwright_#{name}_#{scheme}") do |app|
      Capybara::Playwright::Driver.new(
        app, browser_type: :chromium, headless: ENV["HEADED"].blank?, slowMo: ENV["HEADED"].present? ? 400 : nil,
        viewport: viewport, colorScheme: scheme.to_s, locale: "es-MX",
        playwright_cli_executable_path: Rails.root.join("node_modules/.bin/playwright").to_s
      )
    end
  end
end

Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    viewport = example.metadata.fetch(:viewport, :desktop)
    driven_by :"playwright_#{viewport}_#{example.metadata.fetch(:color_scheme, :light)}"
  end

  # The app server answers from its own thread and its own connection, so it cannot see
  # rows inside the spec's open transaction. System specs commit and clean up after.
  config.around(:each, type: :system) do |example|
    DatabaseCleaner.strategy = :deletion
    example.run
  ensure
    DatabaseCleaner.strategy = :transaction
  end
end
