require "rails_helper"

RSpec.describe "Checkout", type: :request do
  let(:student) { create(:user) }

  def sign_in(user = student)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  it "asks a visitor to sign in first" do
    post checkouts_path(plan: "one_month")

    expect(response).to redirect_to(new_session_path)
  end

  describe "with keys", :stripe do
    before { sign_in }

    it "sends the student to Stripe's hosted page" do
      stub_checkout_session(url: "https://checkout.stripe.com/c/pay/cs_test_77")

      post checkouts_path(plan: "three_months")

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_77")
      expect(
        a_request(:post, BillingHelpers::CHECKOUT_SESSIONS_URL).with do |request|
          Rack::Utils.parse_nested_query(request.body).values_at("success_url", "cancel_url") ==
            ["http://www.example.com/account?checkout=success", "http://www.example.com/pricing"]
        end
      ).to have_been_made
    end

    it "returns to pricing with the reason when the plan is unknown" do
      post checkouts_path(plan: "lifetime")

      expect(response).to redirect_to(pricing_path)
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.unknown_plan"))
    end

    it "throttles repeated attempts" do
      stub_checkout_session

      11.times { post checkouts_path(plan: "one_month") }

      expect(response).to redirect_to(pricing_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
    end
  end

  it "returns to pricing when payments are not configured" do
    sign_in

    post checkouts_path(plan: "one_month")

    expect(response).to redirect_to(pricing_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.unavailable"))
  end
end
