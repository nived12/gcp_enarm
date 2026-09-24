# "Continuar con Google". The middleware is always installed so the app boots the same
# with or without credentials; without them the button is not rendered and the setup
# phase fails before anything is sent to Google (see Identity.google_available?).
#
# OmniAuth 2 accepts only POST on /auth/:provider, and omniauth-rails_csrf_protection
# checks Rails' authenticity token there, so another site cannot start a sign-in in the
# student's browser. Google redirects back with a GET to /auth/google_oauth2/callback.
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
    # Only who the person is: no Google data is read after sign-in, so no refresh token.
    scope: "email,profile", access_type: "online", prompt: "select_account",
    setup: ->(_env) { raise OmniAuth::Error, "not_configured" unless Identity.google_available? }
end

OmniAuth.config.logger = Rails.logger

# The default failure endpoint raises in development instead of redirecting; the
# redirect to /auth/failure is what a student would see, so use it everywhere.
OmniAuth.config.on_failure = ->(env) { OmniAuth::FailureEndpoint.new(env).redirect_to_failure }

# The sign-up form reads the browser's time zone into a hidden field. OmniAuth carries
# only the request's query string to the callback (session["omniauth.params"]), so the
# posted field is added to it here; the callback validates it like the form's.
OmniAuth.config.before_request_phase = lambda do |env|
  time_zone = Rack::Request.new(env).POST["time_zone"]
  env["rack.session"]["omniauth.params"] = env["rack.session"]["omniauth.params"].merge("time_zone" => time_zone.to_s)
end

# With the hosts split, Google sends the student back to the app host whichever host the
# sign-in started on: that is the only callback registered with Google, and OmniAuth
# checks a callback against the session before the router sees it, so one arriving on the
# marketing host would fail there rather than be forwarded. Unsplit, the callback goes to
# the host that was asked, as OmniAuth's own default would.
OmniAuth.config.full_host = lambda do |env|
  request = Rack::Request.new(env)
  SiteHosts.split? ? "#{request.scheme}://#{SiteHosts.app}" : request.base_url
end
