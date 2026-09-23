require "rails_helper"

RSpec.describe Billing::StripeWebhookHandler, :stripe do
  let(:user) { create(:user) }

  def handle(payload, signature: stripe_signature(payload))
    described_class.call(payload: payload, signature: signature)
  end

  def paid_event(id: "evt_1", **session)
    stripe_event_json(id: id, session: checkout_session_payload(user: user, **session))
  end

  it "turns a paid session into an entitlement and records the sale" do
    allow(Analytics).to receive(:capture)

    result = handle(paid_event)

    expect(result.payload).to include(status: :processed)
    expect(user.entitlements.sole).to have_attributes(plan: "three_months", external_id: "cs_test_paid", amount: 449)
    expect(WebhookEvent.sole).to have_attributes(
      provider: "stripe", external_id: "evt_1",
      event_type: "checkout.session.completed"
    )
    expect(Analytics).to have_received(:capture).with(user, "purchase_completed", plan: "three_months", amount: 449.0)
  end

  it "acknowledges a replayed event without acting on it twice" do
    handle(paid_event)

    expect(handle(paid_event).payload).to eq(status: :duplicate)
    expect(Entitlement.count).to eq(1)
  end

  it "grants once when two events report the same session" do
    allow(Analytics).to receive(:capture)
    handle(paid_event(id: "evt_1"))

    result = handle(paid_event(id: "evt_2"))

    expect(result.payload).to include(status: :processed)
    expect(Entitlement.count).to eq(1)
    expect(Analytics).to have_received(:capture).once
  end

  it "records events that grant nothing, so their replays are recognised too" do
    result = handle(paid_event(payment_status: "unpaid"))

    expect(result.payload).to eq(status: :ignored)
    expect(Entitlement.count).to eq(0)
    expect(WebhookEvent.count).to eq(1)
  end

  it "refuses a bad signature" do
    result = handle(paid_event, signature: "t=1,v1=forged")

    expect(result.errors.of_kind?(:base, :invalid_signature)).to be(true)
    expect(WebhookEvent.count).to eq(0)
  end

  it "fails, and forgets the event so Stripe retries it, when the user is unknown" do
    payload = stripe_event_json(session: checkout_session_payload(user: nil))

    result = handle(payload)

    expect(result.errors.full_messages).to eq([I18n.t("billing.webhook.unmatched")])
    expect(WebhookEvent.count).to eq(0)
  end

  it "fails when the plan is not ours" do
    expect(handle(paid_event(plan_code: "lifetime"))).to be_failure
    expect(Entitlement.count).to eq(0)
  end
end
