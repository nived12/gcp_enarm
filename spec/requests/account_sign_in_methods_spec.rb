require "rails_helper"

RSpec.describe "Ways to sign in on /account", type: :request do
  def sign_in_with_google(user)
    user.identities.create!(provider: "google_oauth2", uid: "1", email: "dana.rios@gmail.com")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "1", info: { email: "dana.rios@gmail.com", email_verified: true }
    )
    post "/auth/google_oauth2"
    follow_redirect!
  end

  it "shows the linked Google account, and offers a password to an account without one", :google do
    user = create(:user, password: nil)
    sign_in_with_google(user)

    get account_path

    expect(response.body).to include(I18n.t("identities.account.google_linked", email: "dana.rios@gmail.com"))
    expect(response.body).to include(I18n.t("identities.account.password_missing"), new_password_path)
  end

  it "says Google is not linked and a password is set" do
    user = create(:user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }

    get account_path

    expect(response.body).to include(
      I18n.t("identities.account.google_unlinked"),
      I18n.t("identities.account.password_set")
    )
  end
end
