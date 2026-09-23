require "rails_helper"

RSpec.describe Billing::CheckoutStarter do
  let(:user) { create(:user) }

  def start(plan_code = "one_month")
    described_class.call(
      user: user, plan_code: plan_code, success_url: "https://app.test/account",
      cancel_url: "https://app.test/pricing"
    )
  end

  it "reports checkout unavailable when no keys are configured" do
    result = start

    expect(result).to be_failure
    expect(result.errors.full_messages).to eq([I18n.t("billing.checkout.unavailable")])
    expect(a_request(:any, /stripe\.com/)).not_to have_been_made
  end

  describe "with keys", :stripe do
    it "returns the hosted page's URL and records the intent" do
      stub_checkout_session(url: "https://checkout.stripe.com/c/pay/cs_test_9")
      allow(Analytics).to receive(:capture)

      result = start("twelve_months")

      expect(result.payload).to eq(url: "https://checkout.stripe.com/c/pay/cs_test_9")
      expect(Analytics).to have_received(:capture).with(user, "checkout_started", plan: "twelve_months", amount: 1_099)
    end

    it "refuses a plan that is not in the catalog without calling Stripe" do
      result = start("lifetime")

      expect(result.errors.full_messages).to eq([I18n.t("billing.checkout.unknown_plan")])
      expect(a_request(:any, /stripe\.com/)).not_to have_been_made
    end

    it "fails gently when Stripe refuses, and reports it" do
      stub_request(:post, BillingHelpers::CHECKOUT_SESSIONS_URL).to_return(
        status: 401, headers: { "Content-Type" => "application/json" },
        body: { error: { type: "invalid_request_error", message: "Invalid API Key provided" } }.to_json
      )
      allow(Sentry).to receive(:capture_exception)

      result = start

      expect(result.errors.full_messages).to eq([I18n.t("billing.checkout.failed")])
      expect(Sentry).to have_received(:capture_exception).with(an_instance_of(Stripe::AuthenticationError))
    end
  end
end
