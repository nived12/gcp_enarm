# Stripe in specs: never a live request. Checkout Session creation is answered by a
# WebMock stub of the real endpoint, so the official gem builds the request and parses
# the reply exactly as it would in production; webhooks are signed with Stripe's own
# scheme and a test secret.
#
# Tag an example or group `stripe: true` to run it with keys configured. Without the tag
# the app runs as it does with no keys at all: checkout unavailable, webhooks refused.
module BillingHelpers
  TEST_SECRET_KEY = "sk_test_not_a_real_key".freeze
  TEST_WEBHOOK_SECRET = "whsec_test_not_a_real_secret".freeze
  CHECKOUT_SESSIONS_URL = "https://api.stripe.com/v1/checkout/sessions".freeze

  def stub_checkout_session(url: "https://checkout.stripe.com/c/pay/cs_test_stubbed", id: "cs_test_stubbed")
    stub_request(:post, CHECKOUT_SESSIONS_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: id, object: "checkout.session", url: url }.to_json
    )
  end

  def checkout_session_payload(user:, plan_code: "three_months", id: "cs_test_paid", payment_status: "paid",
                               amount_total: 44_900)
    { id: id, object: "checkout.session", client_reference_id: user&.id&.to_s, amount_total: amount_total,
      currency: "mxn", payment_status: payment_status, payment_intent: "pi_test_1",
      metadata: { user_id: user&.id&.to_s, plan_code: plan_code } }
  end

  # A Charge as `charge.refunded` carries it. Stripe sends the event for partial refunds
  # too; `refunded` is true only once the whole amount is back.
  def refunded_charge_payload(payment_intent: "pi_test_1", amount: 44_900, amount_refunded: amount,
                              refunded: amount_refunded == amount)
    { id: "ch_test_1", object: "charge", amount: amount, amount_refunded: amount_refunded, currency: "mxn",
      payment_intent: payment_intent, refunded: refunded }
  end

  def charge_refunded_json(id: "evt_refund_1", **charge)
    stripe_event_json(type: "charge.refunded", id: id, session: refunded_charge_payload(**charge))
  end

  # A Dispute as `charge.dispute.created` and `charge.dispute.closed` carry it. `created`
  # is when the cardholder opened it; `status` on a closing event is lost, won or
  # warning_closed.
  def dispute_payload(id: "dp_test_1", payment_intent: "pi_test_1", status: "needs_response", created: 2.days.ago)
    { id: id, object: "dispute", amount: 44_900, charge: "ch_test_1", currency: "mxn",
      payment_intent: payment_intent, reason: "fraudulent", status: status, created: created.to_i }
  end

  def dispute_created_json(id: "evt_dispute_1", **dispute)
    stripe_event_json(type: "charge.dispute.created", id: id, session: dispute_payload(**dispute))
  end

  def dispute_closed_json(id: "evt_dispute_closed_1", status: "won", **dispute)
    stripe_event_json(type: "charge.dispute.closed", id: id, session: dispute_payload(status: status, **dispute))
  end

  def stripe_event_json(type: "checkout.session.completed", id: "evt_test_1", session: {})
    { id: id, object: "event", type: type, api_version: "2025-01-01", created: Time.current.to_i,
      data: { object: session } }.to_json
  end

  def stripe_signature(payload, secret: TEST_WEBHOOK_SECRET, time: Time.current)
    signature = Stripe::Webhook::Signature.compute_signature(time, payload, secret)
    Stripe::Webhook::Signature.generate_header(time, signature)
  end
end

RSpec.configure do |config|
  config.include BillingHelpers

  config.around(:each, :stripe) do |example|
    ENV["STRIPE_SECRET_KEY"] = BillingHelpers::TEST_SECRET_KEY
    ENV["STRIPE_WEBHOOK_SECRET"] = BillingHelpers::TEST_WEBHOOK_SECRET
    example.run
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end
end
