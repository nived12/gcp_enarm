require "rails_helper"

RSpec.describe Billing::EntitlementGranter do
  let(:user) { create(:user) }

  before { freeze_time }

  def grant(plan_code, external_id: "cs_#{SecureRandom.hex(4)}")
    described_class.call(
      user: user, plan: Plan.find(plan_code), source: "stripe", external_id: external_id,
      amount: Plan.find(plan_code).price, currency: "MXN", raw_payload: { "id" => external_id }
    )
  end

  it "opens a window from now for the plan's length, recording what was charged" do
    entitlement = grant("three_months").payload[:entitlement]

    expect(entitlement).to have_attributes(
      plan: "three_months", source: "stripe", starts_at: Time.current, expires_at: 3.months.from_now,
      amount: 449, currency: "MXN"
    )
    expect(user).to be_paid_access
  end

  it "starts a second purchase where the open window ends, so renewing early loses no days" do
    grant("one_month")

    second = grant("six_months").payload[:entitlement]

    expect(second).to have_attributes(starts_at: 1.month.from_now, expires_at: 1.month.from_now + 6.months)
    expect(user.paid_access_until).to eq(7.months.from_now)
  end

  it "starts from now once earlier windows have ended" do
    create(:entitlement, user: user, starts_at: 3.months.ago, expires_at: 2.months.ago)

    expect(grant("one_month").payload[:entitlement].starts_at).to eq(Time.current)
  end

  it "queues nothing behind a refunded window, whose days were given back" do
    create(:entitlement, user: user, starts_at: 1.day.ago, expires_at: 29.days.from_now, refunded_at: Time.current)

    expect(grant("one_month").payload[:entitlement].starts_at).to eq(Time.current)
  end

  it "ignores granted premium, which can be withdrawn" do
    user.update!(granted_premium_until: 1.year.from_now)

    expect(grant("one_month").payload[:entitlement].starts_at).to eq(Time.current)
  end

  it "grants a provider's purchase once, however often it is reported" do
    first = grant("one_month", external_id: "cs_same")
    again = grant("one_month", external_id: "cs_same")

    expect(again.payload).to eq(entitlement: first.payload[:entitlement], created: false)
    expect(user.entitlements.count).to eq(1)
  end
end
