require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  let(:user) { create(:user) }
  let(:payload) { stripe_event_json(session: checkout_session_payload(user: user)) }

  def deliver(body, signature: stripe_signature(body))
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Stripe-Signature"] = signature if signature
    post stripe_webhook_path, params: body, headers: headers
  end

  describe "with the endpoint configured", :stripe do
    it "grants the paid window" do
      deliver(payload)

      expect(response).to have_http_status(:ok)
      expect(user).to be_paid_access
    end

    it "answers a replay with 200 and grants nothing more" do
      deliver(payload)
      deliver(payload)

      expect(response).to have_http_status(:ok)
      expect(user.entitlements.count).to eq(1)
    end

    it "rejects a forged signature with 400" do
      deliver(payload, signature: stripe_signature(payload, secret: "whsec_attacker"))

      expect(response).to have_http_status(:bad_request)
      expect(Entitlement.count).to eq(0)
    end

    it "rejects a request with no signature" do
      deliver(payload, signature: nil)

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a body altered after signing" do
      deliver(payload.sub("three_months", "twelve_months"), signature: stripe_signature(payload))

      expect(response).to have_http_status(:bad_request)
    end

    it "answers 422 for a payment it cannot place, and accepts the retry once it can" do
      orphan = stripe_event_json(session: checkout_session_payload(user: user, plan_code: "retired_plan"))
      deliver(orphan)
      expect(response).to have_http_status(:unprocessable_content)

      deliver(payload)
      expect(response).to have_http_status(:ok)
    end

    it "ends the window when its charge is refunded in full" do
      deliver(payload)

      deliver(charge_refunded_json)

      expect(response).to have_http_status(:ok)
      expect(user).not_to be_paid_access
      expect(user.entitlements.sole).to be_refunded
    end

    it "withholds the window while its charge is disputed, and gives it back when the dispute is won" do
      deliver(payload)

      deliver(dispute_created_json)
      expect(response).to have_http_status(:ok)
      expect(user).not_to be_paid_access

      deliver(dispute_closed_json(status: "won"))
      expect(response).to have_http_status(:ok)
      expect(user).to be_paid_access
    end

    it "needs no session, cookie or CSRF token" do
      deliver(payload)

      expect(response.cookies).to be_empty
    end
  end

  it "refuses everything while no webhook secret is set" do
    deliver(payload)

    expect(response).to have_http_status(:bad_request)
  end
end
