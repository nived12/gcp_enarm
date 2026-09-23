# Product analytics, server-side only. Inert without POSTHOG_API_KEY: every call is a
# no-op and no client is built, so development, the test suite and a fresh deploy send
# nothing anywhere.
#
# Server-side on purpose. It sets no cookie in the student's browser, which keeps the
# privacy notice short and the pages free of third-party script.
module Analytics
  DEFAULT_HOST = "https://us.i.posthog.com".freeze

  def self.capture(user, event, properties = {})
    return if client.nil?

    client.capture(distinct_id: user.id.to_s, event: event, properties: properties)
  end

  def self.client
    return if ENV["POSTHOG_API_KEY"].blank?

    @client ||= PostHog::Client.new(api_key: ENV["POSTHOG_API_KEY"], host: ENV.fetch("POSTHOG_HOST", DEFAULT_HOST))
  end

  def self.reset!
    @client = nil
  end
end
