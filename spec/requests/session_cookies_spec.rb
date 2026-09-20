require "rails_helper"

# json 3.0 dropped the positional-options form of JSON.parse that
# ActiveSupport::JSON.decode calls, and the only symptom was that every request
# carrying an encrypted session cookie raised inside cookie decryption. A
# request that never writes to the session cannot catch it — the flash does,
# so a rejected sign-in followed by any other request is the cheapest probe.
RSpec.describe "Encrypted session cookies", type: :request do
  it "decrypts a session cookie written by an earlier request" do
    post session_path, params: { email_address: "nobody@example.com", password: "wrong" }
    expect(response.cookies).to include(Rails.application.config.session_options[:key])

    get root_path
    expect(response).to have_http_status(:ok)
  end
end
