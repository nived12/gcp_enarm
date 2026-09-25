require "rails_helper"

# gpcenarm.com shows the signed-out marketing pages; app.gpcenarm.com is the product.
RSpec.describe "Marketing and app hosts", type: :request do
  let(:landing) { SiteHostsHelpers::LANDING }
  let(:app_host) { SiteHostsHelpers::APP }
  let(:student) { create(:user) }

  def sign_in(user = student)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  def session_cookie
    Array(response.headers["set-cookie"]).join("\n").lines.find { |line| line.start_with?("session_id=") }
  end

  def links
    Nokogiri::HTML(response.body).css("a").pluck("href")
  end

  describe "without LANDING_HOST" do
    it "serves the landing page and the app on one host, with relative links and a host-only cookie" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(links).to include(new_registration_path(from: "hero"), new_session_path, root_path)
      expect(response.body).to include(%(rel="manifest"))

      sign_in
      expect(session_cookie).not_to match(/domain=/i)

      get root_path
      expect(response.body).to include(I18n.t("navigation.sign_out"))
    end
  end

  it "has Google send the student back to the host sign-in started on without LANDING_HOST", :google do
    post "/auth/google_oauth2"

    expect(response.location).to eq("http://www.example.com/auth/google_oauth2/callback")
  end

  describe "with the hosts split", :split_hosts do
    describe "on the marketing host" do
      before { host! landing }

      it "serves the landing page, the prices and the legal pages to a visitor" do
        [root_path, pricing_path, legal_path("privacy")].each do |path|
          get path
          expect(response).to have_http_status(:ok), path
        end
      end

      it "sends every other path to the app host, keeping path and query" do
        get "/exams?page=2&filtro=activo"
        expect(response).to have_http_status(:moved_permanently)
        expect(response.location).to eq("http://#{app_host}/exams?page=2&filtro=activo")

        get "/legal/unknown"
        expect(response.location).to eq("http://#{app_host}/legal/unknown")
      end

      it "keeps the method of a form or webhook sent to the wrong host" do
        post "/webhooks/stripe", params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:permanent_redirect)
        expect(response.location).to eq("http://#{app_host}/webhooks/stripe")
      end

      it "sends the health check, the manifest, the service worker and push to the app" do
        { "/up" => "/up", "/manifest.json" => "/manifest.json", "/service-worker.js" => "/service-worker.js",
          "/push_subscription" => "/push_subscription" }.each do |path, target|
          get path
          expect(response.location).to eq("http://#{app_host}#{target}"), path
        end
      end

      it "points sign-up and sign-in at the app host, keeping where the visitor came from" do
        create(:published_case)
        get root_path

        expect(links).to include(
          "http://#{app_host}#{new_registration_path(from: "hero")}",
          "http://#{app_host}#{new_registration_path(from: "case")}",
          "http://#{app_host}#{new_registration_path(from: "pricing")}",
          "http://#{app_host}#{new_registration_path(from: "closing")}",
          "http://#{app_host}#{new_registration_path(from: "header")}",
          "http://#{app_host}#{new_session_path}",
          pricing_path, "http://#{landing}/"
        )
        expect(links.grep(%r{\A/}).grep_v(%r{\A/(\?|pricing|legal/)})).to be_empty
        expect(response.body).not_to include(%(rel="manifest"))
      end

      it "sends the plan a visitor picks on the prices page to sign up on the app host", :stripe do
        get pricing_path

        expect(links).to include(
          "http://#{app_host}" + new_registration_path(
            return_to: pricing_path(plan: "one_month", anchor: "plan-one_month"), from: "pricing_page"
          )
        )
      end

      it "shows a signed-in student the landing page, with every button leading into the app" do
        create(:published_case)
        host! app_host
        sign_in
        host! landing

        get root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("landing.hero.headline"))
        expect(response.body).not_to include(I18n.t("navigation.sign_in"), I18n.t("navigation.sign_out"), "<form")
        expect(links.count("http://#{app_host}/")).to eq(5)
        expect(links.grep(/registration/)).to be_empty

        get legal_path("terms")
        expect(response).to have_http_status(:ok)
      end

      it "sends a signed-in student to the prices on the app host, where checkout works" do
        host! app_host
        sign_in
        host! landing

        get pricing_path(plan: "one_month")
        expect(response).to redirect_to("http://#{app_host}/pricing?plan=one_month")
        expect(response).to have_http_status(:found)
      end
    end

    it "has Google send the student back to the app host, wherever sign-in started", :google do
      [landing, app_host].each do |host|
        host! host
        post "/auth/google_oauth2"

        expect(response.location).to eq("http://#{app_host}/auth/google_oauth2/callback")
      end
    end

    describe "on the app host" do
      before { host! app_host }

      it "signs in with a cookie the marketing host also reads, and signs out of both" do
        sign_in
        expect(session_cookie).to match(/domain=#{Regexp.escape(landing)}/i)
        expect(session_cookie).to match(/httponly/i).and match(/samesite=lax/i)

        delete session_path
        expect(session_cookie).to match(/domain=#{Regexp.escape(landing)}/i)
          .and match(/max-age=0|expires=Thu, 01 Jan 1970/i)

        host! landing
        get root_path
        expect(response).to have_http_status(:ok)
      end

      it "keeps the cookie host-only on the Railway preview domain" do
        host! "gpcenarm-production.up.railway.app"
        sign_in

        expect(session_cookie).not_to match(/domain=/i)
      end

      it "sends a signed-out visitor at its root to sign in, and a student to their home" do
        get root_path
        expect(response).to redirect_to(new_session_path)

        sign_in
        get root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("navigation.sign_out"))
      end

      it "serves the webhook, the prices and the legal pages itself" do
        post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:bad_request)

        [pricing_path, legal_path("refunds")].each do |path|
          get path
          expect(response).to have_http_status(:ok), path
        end
      end

      it "records the sign-up source a landing link carries across the host change" do
        allow(Analytics).to receive(:capture)
        get new_registration_path(from: "hero")
        post registration_path, params: {
          user: { first_name: "Dana", last_name: "Ríos", email: "nueva@example.com", password: "contrasena-segura",
                  password_confirmation: "contrasena-segura" }
        }

        expect(Analytics).to have_received(:capture).with(User.sole, "signed_up", hash_including(source: "hero"))
      end
    end
  end
end
