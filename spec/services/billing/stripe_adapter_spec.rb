require "rails_helper"

RSpec.describe Billing::StripeAdapter do
  let(:user) { create(:user) }
  let(:adapter) { described_class.new }

  def event(type: "checkout.session.completed", **session_attributes)
    payload = stripe_event_json(type: type, session: checkout_session_payload(user: user, **session_attributes))
    adapter.verified_event(payload, stripe_signature(payload))
  end

  it "is unavailable without a secret key" do
    expect(described_class).not_to be_checkout_available
  end

  describe "with keys", :stripe do
    it "is available" do
      expect(described_class).to be_checkout_available
    end

    it "opens a one-time MXN Checkout Session priced from our own catalog" do
      stub_checkout_session(url: "https://checkout.stripe.com/c/pay/cs_test_42")

      url = adapter.create_checkout_session(
        user: user, plan: Plan.find("six_months"), success_url: "https://app.test/account", cancel_url: "https://app.test/pricing"
      )

      expect(url).to eq("https://checkout.stripe.com/c/pay/cs_test_42")
      expect(
        a_request(:post, BillingHelpers::CHECKOUT_SESSIONS_URL).with do |request|
          body = Rack::Utils.parse_nested_query(request.body)
          request.headers["Authorization"] == "Bearer #{BillingHelpers::TEST_SECRET_KEY}" &&
            body["mode"] == "payment" &&
            body["line_items"] == {
              "0" => { "quantity" => "1",
                       "price_data" => { "currency" => "mxn", "unit_amount" => "74900",
                                         "product_data" => { "name" => "GPCEnarm · 6 meses de acceso" } } }
            } &&
            body["client_reference_id"] == user.id.to_s && body["customer_email"] == user.email &&
            body["metadata"] == { "user_id" => user.id.to_s, "plan_code" => "six_months" } &&
            body["payment_intent_data"] == { "metadata" => { "user_id" => user.id.to_s,
"plan_code" => "six_months" } } &&
            body["success_url"] == "https://app.test/account" && body["cancel_url"] == "https://app.test/pricing"
        end
      ).to have_been_made.once
    end

    it "accepts an event signed with the webhook secret" do
      expect(event.id).to eq("evt_test_1")
    end

    it "rejects a forged, stale or missing signature" do
      payload = stripe_event_json

      expect { adapter.verified_event(payload, stripe_signature(payload, secret: "whsec_other")) }
        .to raise_error(Stripe::SignatureVerificationError)
      expect { adapter.verified_event(payload, stripe_signature(payload, time: 10.minutes.ago)) }
        .to raise_error(Stripe::SignatureVerificationError)
      expect { adapter.verified_event(payload, nil) }.to raise_error(Stripe::SignatureVerificationError)
    end

    it "reads a paid session as a purchase, in pesos" do
      expect(adapter.purchase_from(event)).to include(
        user_id: user.id.to_s, plan_code: "three_months", external_id: "cs_test_paid",
        amount: BigDecimal("449"), currency: "MXN"
      )
    end

    it "keeps the whole session as the raw payload" do
      expect(adapter.purchase_from(event)[:raw_payload]).to include(id: "cs_test_paid", payment_intent: "pi_test_1")
    end

    it "does not count a completed session that is still unpaid, as OXXO leaves it" do
      expect(adapter.purchase_from(event(payment_status: "unpaid"))).to be_nil
    end

    it "counts the later OXXO payment" do
      purchase = adapter.purchase_from(event(type: "checkout.session.async_payment_succeeded", payment_status: "paid"))

      expect(purchase).to include(external_id: "cs_test_paid")
    end

    it "ignores every other event" do
      expect(adapter.purchase_from(event(type: "checkout.session.expired"))).to be_nil
    end

    describe "refunds" do
      def refund_event(**charge)
        payload = charge_refunded_json(**charge)
        adapter.verified_event(payload, stripe_signature(payload))
      end

      it "reads a fully refunded charge, in pesos, by its PaymentIntent" do
        expect(adapter.refund_from(refund_event)).to eq(
          payment_intent: "pi_test_1", refunded_amount: BigDecimal("449"), full: true
        )
      end

      it "reads a partial refund as the running total, not as a full one" do
        expect(adapter.refund_from(refund_event(amount_refunded: 10_050))).to eq(
          payment_intent: "pi_test_1", refunded_amount: BigDecimal("100.5"), full: false
        )
      end

      it "reads no refund out of any other event" do
        expect(adapter.refund_from(event)).to be_nil
      end
    end
  end

  describe "without a webhook secret" do
    it "trusts nothing" do
      payload = stripe_event_json

      expect { adapter.verified_event(payload, stripe_signature(payload)) }.to raise_error(Stripe::SignatureVerificationError)
    end
  end
end
