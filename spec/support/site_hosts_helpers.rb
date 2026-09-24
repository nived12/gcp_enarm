# Tag an example or group `split_hosts: true` to run it with the marketing site and the app
# on their production hosts. Untagged, LANDING_HOST is unset and there is no split.
module SiteHostsHelpers
  LANDING = "gpcenarm.com".freeze
  APP = "app.gpcenarm.com".freeze
end

RSpec.configure do |config|
  config.around(:each, :split_hosts) do |example|
    Rails.configuration.x.landing_host = SiteHostsHelpers::LANDING
    Rails.configuration.x.app_host = SiteHostsHelpers::APP
    example.run
  ensure
    Rails.configuration.x.landing_host = nil
    Rails.configuration.x.app_host = nil
  end
end
