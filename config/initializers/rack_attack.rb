# A coarse, IP-level shield in front of the per-controller `rate_limit`s: those protect
# one form each, this one also caps a single address hammering the whole app and a
# single account being guessed at from many addresses.
#
# Counters live in Rails.cache (Solid Cache in production). The test environment's
# :null_store never counts, so these rules are inert in specs except where one installs
# a real store — see spec/requests/rack_attack_spec.rb.
class Rack::Attack
  # Stripe retries webhooks on its own schedule and signs every one; throttling it would
  # only delay a student's access.
  safelist("webhooks") { |request| request.path.start_with?("/webhooks/") }

  safelist("health check") { |request| request.path == "/up" }

  throttle("requests per ip", limit: 300, period: 5.minutes) do |request|
    request.ip unless request.path.start_with?("/assets/")
  end

  throttle("sign-in per ip", limit: 20, period: 5.minutes) do |request|
    request.ip if request.post? && request.path == "/session"
  end

  throttle("sign-in per email", limit: 10, period: 15.minutes) do |request|
    request.params["email"].to_s.strip.downcase.presence if request.post? && request.path == "/session"
  end

  throttle("sign-up per ip", limit: 20, period: 1.hour) do |request|
    request.ip if request.post? && request.path == "/registration"
  end

  throttle("password reset per ip", limit: 10, period: 15.minutes) do |request|
    request.ip if request.path.start_with?("/passwords") && !request.get?
  end

  throttle("password reset per email", limit: 5, period: 1.hour) do |request|
    request.params["email"].to_s.strip.downcase.presence if request.post? && request.path == "/passwords"
  end

  self.throttled_responder = lambda do |_request|
    [ 429, { "content-type" => "text/plain; charset=utf-8", "retry-after" => "60" },
      [ I18n.t("sessions.create.rate_limited") ] ]
  end
end
