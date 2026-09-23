# Error tracking, inert without SENTRY_DSN: Sentry is never initialised, and
# Sentry.capture_* return without doing anything. The defaults already withhold IPs,
# cookies and request bodies — students' answers and emails stay here.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0).to_f
  end
end
