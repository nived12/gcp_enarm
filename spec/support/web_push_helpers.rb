# Tag an example or group `web_push: true` to run it with a VAPID pair configured, the way
# production is once the keys are set. Everything else runs as a fresh checkout does:
# no keys, and Web Push invisible.
module WebPushHelpers
  VAPID = WebPush.generate_key

  def self.with_keys
    previous = ENV.to_h.slice("VAPID_PUBLIC_KEY", "VAPID_PRIVATE_KEY")
    ENV["VAPID_PUBLIC_KEY"] = VAPID.public_key
    ENV["VAPID_PRIVATE_KEY"] = VAPID.private_key
    yield
  ensure
    %w[VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY].each { |key| ENV[key] = previous[key] }
  end
end

RSpec.configure do |config|
  config.around(:each, :web_push) { |example| WebPushHelpers.with_keys { example.run } }
end
