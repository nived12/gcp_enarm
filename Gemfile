source "https://rubygems.org"

gem "rails", "~> 8.1.3", ">= 8.1.3.1"

# json 3.0 dropped the positional-options form of JSON.parse, which
# ActiveSupport::JSON.decode still calls. Every request carrying an encrypted
# cookie raises ArgumentError inside session decryption. Unpin once Rails ships
# a release that passes keyword options.
gem "json", "~> 2.9"

# Spanish translations for everything Rails itself emits — validation messages,
# date formats, distance_of_time_in_words. default_locale is :es and the fallback
# chain for :es does not reach :en, so without this the UI renders
# "Translation missing" to students.
gem "rails-i18n"

# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Environment variables
gem "dotenv-rails"

# HTTP client for the GPC catalog and the LLM providers
gem "httparty"

# HTML parsing for the DDIMBE catalog and guideline sections
gem "nokogiri"

# Text extraction from the archived GPC PDFs (text-based, so no OCR)
gem "pdf-reader"

# Pagination
gem "pagy"

# Soft delete/archiving
gem "discard", "~> 1.3"

# Icon library
gem "rails_icons"

# Markdown rendering for content pages (CommonMark, safe by default)
gem "commonmarker", "~> 2.0"

# Payments and subscriptions
gem "pay"
gem "stripe"

# Transactional email
gem "resend"

# Rate limiting
gem "rack-attack"

# Error tracking
gem "sentry-ruby"
gem "sentry-rails"

# Analytics
gem "posthog-ruby", require: "posthog"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  gem "capybara"
  # Drives a real browser for the few end-to-end flows a student depends on. The Ruby
  # client talks to the `playwright` npm package, whose version must match it — see
  # spec/support/playwright.rb.
  gem "capybara-playwright-driver"
  gem "database_cleaner-active_record"
  gem "webmock"                          # HTTP stubbing; also the guard against live LLM calls in specs
  gem "parallel_tests", require: false   # Splits the suite across CPU cores — see bin/ci-test
  gem "simplecov", require: false        # Coverage report; merges across parallel processes
end
