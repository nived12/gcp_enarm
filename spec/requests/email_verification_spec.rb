require "rails_helper"

# A password sign-up proves its address before it can use anything; the link it is sent
# works from any browser, signed in or not.
RSpec.describe "Email verification", type: :request do
  let(:user) { create(:user, :unverified, email: "dana@example.com", first_name: "Dana") }

  def sign_in(account = user)
    post session_path, params: { email: account.email, password: "contrasena-segura" }
  end

  def link_for(account = user)
    verify_email_path(account.generate_token_for(:email_verification))
  end

  describe "an unverified account" do
    before { sign_in }

    it "is sent to the waiting page on signing in" do
      expect(response).to redirect_to(email_verification_path)
      follow_redirect!

      expect(response.body).to include(I18n.t("email_verifications.show.subtitle", email: "dana@example.com"))
    end

    it "is kept out of every page that uses the platform" do
      [root_path, exams_path, new_exam_path, account_path, stats_path, reviews_path, study_plan_path].each do |path|
        get path
        expect(response).to redirect_to(email_verification_path), path
      end
      post checkouts_path, params: { plan: "six_months" }
      expect(response).to redirect_to(email_verification_path)
    end

    it "can still read the prices and the legal pages, and sign out" do
      get pricing_path
      expect(response).to have_http_status(:ok)
      get legal_path("privacy")
      expect(response).to have_http_status(:ok)

      delete session_path
      expect(response).to redirect_to(root_path)
      expect(user.sessions).to be_empty
    end

    it "can ask for another link, a few times" do
      expect { post email_verification_path }.to have_enqueued_mail(EmailVerificationsMailer, :verify)
      expect(response).to redirect_to(email_verification_path)
      expect(flash[:notice]).to eq(I18n.t("email_verifications.create.sent"))

      2.times { post email_verification_path }
      expect { post email_verification_path }.not_to have_enqueued_mail
      expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
    end

    it "is verified by its link and goes home, with the trial counted from now" do
      travel_to 2.days.from_now

      get link_for

      expect(response).to redirect_to(root_url)
      expect(flash[:notice]).to eq(I18n.t("email_verifications.confirm.verified"))
      expect(user.reload.email_verified_at).to eq(Time.current)
      expect(user.trial_ends_at).to be_within(1.second).of(SubscriptionAccess.trial_days.days.from_now)
      follow_redirect!
      expect(response.body).to include(I18n.t("home.dashboard.greeting", name: "Dana"))
    end

    it "keeps the waiting page when the link is wrong" do
      get verify_email_path("no-es-un-token")

      expect(response).to redirect_to(email_verification_path)
      expect(flash[:alert]).to eq(I18n.t("email_verifications.confirm.invalid"))
      expect(user.reload).not_to be_email_verified
    end

    it "refuses a link older than three days" do
      link = link_for
      travel 3.days + 1.minute

      get link

      expect(user.reload).not_to be_email_verified
    end

    it "refuses a link sent to an address the account no longer has" do
      link = link_for
      user.update!(email: "otra@example.com")

      get link

      expect(user.reload).not_to be_email_verified
    end

    it "keeps a way back to /pricing until the address is proven" do
      delete session_path
      get new_session_path(return_to: pricing_path(plan: "six_months"))
      sign_in
      expect(response).to redirect_to(email_verification_path)

      get link_for

      expect(response).to redirect_to("http://www.example.com#{pricing_path(plan: "six_months")}")
    end
  end

  describe "the link opened signed out, on another device" do
    it "verifies the account and asks to sign in" do
      get link_for

      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("email_verifications.confirm.verified_sign_in"))
      expect(user.reload).to be_email_verified
    end

    it "says so when the link is wrong" do
      get verify_email_path("no-es-un-token")

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("email_verifications.confirm.invalid"))
    end

    it "does not restart the trial of an account already verified" do
      verified = create(:user)
      trial = verified.trial_ends_at
      travel 1.day

      get link_for(verified)

      expect(verified.reload.trial_ends_at).to eq(trial)
    end
  end

  describe "a verified account" do
    before { sign_in(create(:user)) }

    it "has no waiting page to see and no link to ask for" do
      get email_verification_path
      expect(response).to redirect_to(root_path)

      expect { post email_verification_path }.not_to have_enqueued_mail
      expect(response).to redirect_to(root_path)
    end
  end

  it "sends a visitor with no account to sign in" do
    get email_verification_path

    expect(response).to redirect_to(new_session_path)
  end

  it "counts a password reset as proof of the address" do
    token = user.password_reset_token

    put password_path(token), params: { password: "otra-contrasena", password_confirmation: "otra-contrasena" }

    expect(user.reload).to be_email_verified
  end
end
