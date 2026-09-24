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

  describe "charge.refunded" do
    let!(:sale) do
      create(
        :entitlement, user: user, plan: "three_months", amount: 449, starts_at: 1.day.ago,
        expires_at: 3.months.from_now, raw_payload: checkout_session_payload(user: user)
      )
    end

    it "withdraws a fully refunded window and records the refund" do
      allow(Analytics).to receive(:capture)

      result = handle(charge_refunded_json)

      expect(result.payload).to eq(status: :refunded, entitlement: sale)
      expect(sale.reload).to be_refunded
      expect(user).not_to be_paid_access
      expect(WebhookEvent.sole).to have_attributes(external_id: "evt_refund_1", event_type: "charge.refunded")
      expect(Analytics).to have_received(:capture).with(user, "purchase_refunded", plan: "three_months", amount: 449.0)
    end

    it "keeps access through a partial refund, and reports no refund to analytics" do
      allow(Analytics).to receive(:capture)

      handle(charge_refunded_json(amount_refunded: 10_000))

      expect(sale.reload).to have_attributes(refunded_amount: 100, refunded_at: nil)
      expect(user).to be_paid_access
      expect(Analytics).not_to have_received(:capture)
    end

    it "acknowledges a replayed refund without acting on it twice" do
      handle(charge_refunded_json)

      expect(handle(charge_refunded_json).payload).to eq(status: :duplicate)
    end

    it "fails, so Stripe retries and shows it, when no sale has that PaymentIntent" do
      result = handle(charge_refunded_json(payment_intent: "pi_someone_else"))

      expect(result.errors.full_messages).to eq([I18n.t("billing.webhook.unmatched_refund")])
      expect(WebhookEvent.count).to eq(0)
      expect(sale.reload).not_to be_refunded
    end

    it "fails for a charge with no PaymentIntent, which no Checkout sale has" do
      expect(handle(charge_refunded_json(payment_intent: nil))).to be_failure
    end
  end

  describe "charge.dispute.created and charge.dispute.closed" do
    let!(:sale) do
      create(
        :entitlement, user: user, plan: "three_months", amount: 449, starts_at: 1.day.ago,
        expires_at: 3.months.from_now, raw_payload: checkout_session_payload(user: user)
      )
    end

    before { allow(Analytics).to receive(:capture) }

    it "withholds the disputed window and records the dispute" do
      result = handle(dispute_created_json)

      expect(result.payload).to eq(status: :disputed, entitlement: sale)
      expect(sale.reload).to have_attributes(dispute_id: "dp_test_1", dispute_status: "open")
      expect(user).not_to be_paid_access
      expect(WebhookEvent.sole).to have_attributes(external_id: "evt_dispute_1", event_type: "charge.dispute.created")
      expect(Analytics).to have_received(:capture).with(user, "purchase_disputed", plan: "three_months", amount: 449.0)
    end

    it "gives access back when the dispute is won" do
      handle(dispute_created_json)

      handle(dispute_closed_json(status: "won"))

      expect(sale.reload).to be_dispute_won
      expect(user).to be_paid_access
      expect(Analytics).to have_received(:capture)
        .with(user, "dispute_closed", plan: "three_months", amount: 449.0, outcome: "won")
    end

    it "keeps access withdrawn when the dispute is lost" do
      handle(dispute_created_json)

      handle(dispute_closed_json(status: "lost"))

      expect(sale.reload).to be_dispute_lost
      expect(user).not_to be_paid_access
      expect(Analytics).to have_received(:capture)
        .with(user, "dispute_closed", plan: "three_months", amount: 449.0, outcome: "lost")
    end

    it "acknowledges a replayed dispute without acting on it twice" do
      handle(dispute_created_json)

      expect(handle(dispute_created_json).payload).to eq(status: :duplicate)
      expect(Analytics).to have_received(:capture).once
    end

    it "reports nothing to analytics when a late opening event changes nothing" do
      handle(dispute_closed_json(status: "won"))

      result = handle(dispute_created_json)

      expect(result.payload).to eq(status: :disputed, entitlement: sale)
      expect(user).to be_paid_access
      expect(Analytics).to have_received(:capture).once
    end

    it "fails, so Stripe retries and shows it, when no sale has that PaymentIntent" do
      result = handle(dispute_created_json(payment_intent: "pi_someone_else"))

      expect(result.errors.full_messages).to eq([I18n.t("billing.webhook.unmatched_dispute")])
      expect(WebhookEvent.count).to eq(0)
      expect(user).to be_paid_access
    end
  end
end
