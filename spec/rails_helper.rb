require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"

# Never let a spec run against production — DatabaseCleaner truncates.
if Rails.env.production?
  abort("RSpec attempted to run in PRODUCTION. Aborting before DatabaseCleaner touches anything.")
end

require "rspec/rails"
require "database_cleaner/active_record"
require "webmock/rspec"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Views reference the built stylesheet; a fresh checkout has no app/assets/builds.
if !File.exist?(Rails.root.join("app/assets/builds/application.css"))
  puts "Building assets for the test environment..."
  system("yarn build && yarn build:css")
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = false

  config.before(:each) do
    I18n.locale = :es
  end

  config.before(:suite) do
    if Rails.env.production?
      raise "DatabaseCleaner attempted to run in PRODUCTION. This would destroy production data."
    end

    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveJob::TestHelper
  config.include ActiveSupport::Testing::TimeHelpers

  config.before(:each) do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
