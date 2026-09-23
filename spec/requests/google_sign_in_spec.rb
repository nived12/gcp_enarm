require "rails_helper"

# Every example goes through the real OmniAuth middleware in test mode: the POST is the
# request phase, the redirect it answers with is the callback.
RSpec.describe "Signing in with Google", type: :request do
  def continue_with_google(time_zone: "")
    post "/auth/google_oauth2", params: { time_zone: time_zone }
    follow_redirect!
  end

  describe "without credentials" do
    it "shows no button and refuses to start" do
      get new_session_path
      expect(response.body).not_to include(I18n.t("identities.google.continue"))

      post "/auth/google_oauth2"

      expect(response).to redirect_to("/auth/failure?message=not_configured&strategy=google_oauth2")
    end
  end

  describe "with credentials", :google do
    it "offers the button on sign-in and sign-up, carrying the browser's zone" do
      [new_session_path, new_registration_path].each do |path|
        get path

        form = Nokogiri::HTML(response.body).at_css("form[action='/auth/google_oauth2']")
        expect(form["method"]).to eq("post")
        expect(form["data-turbo"]).to eq("false")
        expect(form.at_css("input[name=time_zone][data-controller=time-zone]")).to be_present
        expect(form.text).to include(I18n.t("identities.google.continue"))
      end
    end

    it "only starts on a POST" do
      get "/auth/google_oauth2"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a POST without the authenticity token, before any redirect to Google" do
      ActionController::Base.allow_forgery_protection = true
      mock_google

      post "/auth/google_oauth2"

      expect(response.location).to start_with("/auth/failure?message=")
      expect(User.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "starts with a valid authenticity token" do
      ActionController::Base.allow_forgery_protection = true
      mock_google
      get new_session_path
      form = Nokogiri::HTML(response.body).at_css("form[action='/auth/google_oauth2']")
      token = form.at_css("input[name=authenticity_token]")["value"]

      post "/auth/google_oauth2", params: { authenticity_token: token }

      expect(response.location).to eq("http://www.example.com/auth/google_oauth2/callback")
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    describe "a new person" do
      it "gets an account with Google's names, the trial, no password and the browser's zone" do
        freeze_time
        mock_google

        expect { continue_with_google(time_zone: "America/Cancun") }.to change(User, :count).by(1)

        user = User.find_by!(email: "dana.rios@gmail.com")
        expect([ user.first_name, user.last_name, user.time_zone ]).to eq([ "Dana", "Ríos Vega", "America/Cancun" ])
        expect(user.trial_ends_at).to eq(SubscriptionAccess.trial_days.days.from_now)
        expect(user).to be_role_student
        expect(user.password?).to be(false)
        expect(user.identities.sole).to have_attributes(provider: "google", uid: "108000000000000000001")
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("identities.outcomes.created"))

        follow_redirect!
        expect(response.body).to include(I18n.t("home.dashboard.greeting", name: "Dana"))
      end

      it "keeps the default zone for one tzinfo does not know" do
        mock_google

        continue_with_google(time_zone: "Mars/Olympus_Mons")

        expect(User.sole.time_zone).to eq("America/Mexico_City")
      end

      it "falls back to the display name, then the address, when Google has no given name" do
        mock_google(first_name: nil, last_name: nil, name: "Dana")
        continue_with_google
        expect([ User.sole.first_name, User.sole.last_name ]).to eq([ "Dana", nil ])

        delete session_path
        mock_google(uid: "2", email: "sin.nombre@gmail.com", first_name: nil, last_name: nil, name: nil)
        continue_with_google
        expect(User.find_by!(email: "sin.nombre@gmail.com").first_name).to eq("sin.nombre")
      end

      it "is refused when Google has not verified the address" do
        mock_google(verified: false)

        expect { continue_with_google }.not_to change(User, :count)

        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("identities.unverified.create"))
      end

      it "is refused when Google gives no address at all" do
        mock_google(email: nil, verified: false)

        continue_with_google

        expect(flash[:alert]).to eq(I18n.t("identities.unverified.create"))
      end
    end

    describe "an existing account with the same address" do
      let!(:user) { create(:user, email: "dana.rios@gmail.com", first_name: "Dana", last_name: "Ríos") }

      it "is linked and signed in when Google verified the address" do
        mock_google(email: "Dana.Rios@Gmail.com")

        expect { continue_with_google }.not_to change(User, :count)

        expect(user.identities.sole.email).to eq("dana.rios@gmail.com")
        expect(flash[:notice]).to eq(I18n.t("identities.outcomes.linked"))
        expect(user.reload.password?).to be(true)
        expect(user.last_name).to eq("Ríos")
      end

      it "is left alone when Google has not verified the address" do
        mock_google(verified: false)

        continue_with_google

        expect(user.identities).to be_empty
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("identities.unverified.link"))
        get root_path
        expect(response.body).not_to include(I18n.t("home.dashboard.greeting", name: "Dana"))
      end

      it "is not linked to a second Google account" do
        user.identities.create!(provider: "google_oauth2", uid: "otro", email: "antes@gmail.com")
        mock_google

        continue_with_google

        expect(user.identities.sole.uid).to eq("otro")
        expect(flash[:alert]).to eq(I18n.t("identities.already_linked"))
      end
    end

    describe "a returning Google user" do
      let!(:user) { create(:user, first_name: "Dana", email: "dana@example.com") }

      before do
        user.identities.create!(provider: "google_oauth2", uid: "108000000000000000001", email: "vieja@gmail.com")
      end

      it "is signed in by Google's id even after changing the address there" do
        mock_google(email: "nueva@gmail.com")

        continue_with_google

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("identities.outcomes.returning"))
        expect(user.identities.sole.email).to eq("nueva@gmail.com")
        expect(user.sessions.count).to eq(1)
      end

      it "keeps the address on file when Google sends none" do
        mock_google(email: nil, verified: false)

        continue_with_google

        expect(user.sessions.count).to eq(1)
        expect(user.identities.sole.email).to eq("vieja@gmail.com")
      end

      it "goes back to the plan chosen on /pricing" do
        mock_google
        chosen = pricing_path(plan: "six_months")

        get new_session_path(return_to: chosen)
        continue_with_google

        expect(response).to redirect_to("http://www.example.com#{chosen}")
      end
    end

    describe "failure" do
      it "says so in Spanish when the student cancels on Google's consent screen" do
        OmniAuth.config.mock_auth[:google_oauth2] = :access_denied

        continue_with_google
        expect(response).to redirect_to("/auth/failure?message=access_denied&strategy=google_oauth2")
        follow_redirect!

        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("identities.failure.cancelled"))
      end

      it "gives a general message for anything else" do
        get omniauth_failure_path(message: "invalid_credentials", strategy: "google_oauth2")

        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("identities.failure.failed"))
      end
    end
  end
end
