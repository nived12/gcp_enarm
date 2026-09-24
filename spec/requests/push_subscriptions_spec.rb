require "rails_helper"

RSpec.describe "Push subscriptions", type: :request do
  let(:student) { create(:user) }
  let(:endpoint) { "https://web.push.apple.com/QGx1c2VyLWRldmljZQ" }
  let(:keys) { attributes_for(:push_subscription).slice(:p256dh_key, :auth_key) }
  let(:params) do
    { push_subscription: { endpoint: endpoint, keys: { p256dh: keys[:p256dh_key], auth: keys[:auth_key] } } }
  end

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  context "with Web Push configured", :web_push do
    it "saves the browser's subscription for the signed-in student" do
      post push_subscription_path, params: params, as: :json

      expect(response).to have_http_status(:created)
      expect(student.push_subscriptions.sole).to have_attributes(endpoint: endpoint, p256dh_key: keys[:p256dh_key])
    end

    it "moves a device already on file to whoever is signed in on it now" do
      create(:push_subscription, endpoint: endpoint)

      post push_subscription_path, params: params, as: :json

      expect(PushSubscription.sole.user).to eq(student)
    end

    it "refuses an endpoint that is not a browser push service" do
      params[:push_subscription][:endpoint] = "https://attacker.example/collect"

      post push_subscription_path, params: params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(PushSubscription.count).to eq(0)
    end

    it "refuses a subscription without its keys" do
      post push_subscription_path, params: { push_subscription: { endpoint: endpoint } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forgets this device, and only this student's copy of it" do
      mine = create(:push_subscription, user: student, endpoint: endpoint)
      theirs = create(:push_subscription)

      delete push_subscription_path, params: { endpoint: mine.endpoint }, as: :json
      delete push_subscription_path, params: { endpoint: theirs.endpoint }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.all).to eq([theirs])
    end
  end

  it "does not exist until Web Push is configured" do
    post push_subscription_path, params: params, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "asks a visitor to sign in", :web_push do
    delete session_path

    post push_subscription_path, params: params, as: :json

    expect(response).to redirect_to(new_session_path)
  end
end
