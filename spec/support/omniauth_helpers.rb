# Google sign-in without Google: OmniAuth's test mode answers the request phase with a
# redirect straight to the callback and hands the callback whatever mock_auth holds.
# Tag an example `:google` to switch the feature on for it.
module OmniauthHelpers
  def mock_google(uid: "108000000000000000001", email: "dana.rios@gmail.com", verified: true,
                  first_name: "Dana", last_name: "Ríos Vega", name: "Dana Ríos Vega")
    info = { "name" => name, "first_name" => first_name, "last_name" => last_name,
             "unverified_email" => email, "email_verified" => verified }
    info["email"] = email if verified
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      "provider" => "google_oauth2", "uid" => uid, "info" => info.compact
    )
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers

  config.around(:each, :google) do |example|
    ENV["GOOGLE_CLIENT_ID"] = "test-client-id.apps.googleusercontent.com"
    ENV["GOOGLE_CLIENT_SECRET"] = "test-client-secret"
    OmniAuth.config.test_mode = true
    example.run
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
    ENV.delete("GOOGLE_CLIENT_ID")
    ENV.delete("GOOGLE_CLIENT_SECRET")
  end
end
