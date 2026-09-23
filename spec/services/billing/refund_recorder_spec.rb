require "rails_helper"

RSpec.describe Billing::RefundRecorder do
  let(:user) { create(:user, :trial_expired) }

  before { freeze_time }

  def window(from, to, **attributes)
    create(:entitlement, user: user, starts_at: from, expires_at: to, amount: 199, **attributes)
  end

  def refund(entitlement, amount: entitlement.amount, full: true)
    described_class.call(entitlement: entitlement, refunded_amount: amount, full: full)
  end

  it "withdraws a fully refunded window from now, keeping the sale and its dates" do
    current = window(10.days.ago, 20.days.from_now)

    result = refund(current)

    expect(result.payload).to eq(entitlement: current, revoked: true)
    expect(current.reload).to have_attributes(
      refunded_at: Time.current, refunded_amount: 199,
      starts_at: 10.days.ago, expires_at: 20.days.from_now, amount: 199
    )
    expect(user).not_to be_paid_access
    expect(user.paid_access_until).to be_nil
  end

  it "records a partial refund and leaves the window granting access" do
    current = window(1.day.ago, 29.days.from_now)

    result = refund(current, amount: 50, full: false)

    expect(result.payload[:revoked]).to be(false)
    expect(current.reload).to have_attributes(refunded_at: nil, refunded_amount: 50)
    expect(current).to be_partially_refunded
    expect(user).to be_paid_access
  end

  it "takes the provider's running total, so a replay or an older event counts nothing twice" do
    current = window(1.day.ago, 29.days.from_now)
    refund(current, amount: 80, full: false)

    refund(current, amount: 80, full: false)
    refund(current, amount: 30, full: false)

    expect(current.reload.refunded_amount).to eq(80)
  end

  it "withdraws access once, and never gives it back" do
    current = window(1.day.ago, 29.days.from_now)
    refund(current)
    travel 1.hour

    again = refund(current, amount: 50, full: false)

    expect(again.payload[:revoked]).to be(false)
    expect(current.reload).to have_attributes(refunded_at: 1.hour.ago, refunded_amount: 199)
    expect(current).not_to be_partially_refunded
  end

  it "moves a window queued behind the refunded one to start now, so no paid day is lost" do
    current = window(10.days.ago, 20.days.from_now)
    queued = window(20.days.from_now, 110.days.from_now)
    after_that = window(110.days.from_now, 140.days.from_now)

    refund(current)

    expect(queued.reload).to have_attributes(starts_at: Time.current, expires_at: 90.days.from_now)
    expect(after_that.reload).to have_attributes(starts_at: 90.days.from_now, expires_at: 120.days.from_now)
    expect(user).to be_paid_access
    expect(user.paid_access_until).to eq(120.days.from_now)
  end

  it "moves later windows back by the whole length of a refunded window that had not started" do
    current = window(10.days.ago, 20.days.from_now)
    refunded = window(20.days.from_now, 50.days.from_now)
    later = window(50.days.from_now, 80.days.from_now)

    refund(refunded)

    expect(current.reload).to have_attributes(starts_at: 10.days.ago, expires_at: 20.days.from_now)
    expect(later.reload).to have_attributes(starts_at: 20.days.from_now, expires_at: 50.days.from_now)
  end

  it "moves nothing when the refunded window had already ended" do
    ended = window(40.days.ago, 10.days.ago)
    later = window(5.days.ago, 25.days.from_now)

    refund(ended)

    expect(ended.reload).to be_refunded
    expect(later.reload).to have_attributes(starts_at: 5.days.ago, expires_at: 25.days.from_now)
  end

  it "leaves windows that were already refunded where they are" do
    current = window(1.day.ago, 29.days.from_now)
    earlier_refund = window(29.days.from_now, 59.days.from_now, refunded_at: 1.day.ago, refunded_amount: 199)

    refund(current)

    expect(earlier_refund.reload).to have_attributes(starts_at: 29.days.from_now, expires_at: 59.days.from_now)
  end
end
