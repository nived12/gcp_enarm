# Product analytics, server-side only. Inert without POSTHOG_API_KEY: every call is a
# no-op and no client is built, so development, the test suite and a fresh deploy send
# nothing anywhere.
#
# Server-side on purpose. It sets no cookie in the student's browser, which keeps the
# privacy notice short and the pages free of third-party script. The distinct id is the
# user's id and nothing else identifies them: never put a name, an email or free text a
# student typed into an event.
#
# Events are milestones, never one per answer: a student answers about a hundred
# questions a day, and PostHog's free tier is a million events a month in total.
module Analytics
  DEFAULT_HOST = "https://us.i.posthog.com".freeze

  # posthog-ruby only queues here; the HTTP request runs on its own worker thread, which
  # rescues and reports its own failures, so PostHog being down never reaches a request.
  # What can still raise on the caller's thread is the client refusing a malformed
  # event (FieldParser raises ArgumentError), and the test suite never builds a client
  # to catch that — so a bad call is logged and dropped rather than failing the page.
  def self.capture(user, event, properties = {})
    return if client.nil?

    client.capture(distinct_id: user.id.to_s, event: event, properties: properties)
  rescue StandardError => error
    Rails.logger.error("Analytics dropped #{event}: #{error.class}: #{error.message}")
    nil
  end

  def self.client
    return if ENV["POSTHOG_API_KEY"].blank?

    @client ||= PostHog::Client.new(api_key: ENV["POSTHOG_API_KEY"], host: ENV.fetch("POSTHOG_HOST", DEFAULT_HOST))
  end

  def self.reset!
    @client = nil
  end
end
