require "rails_helper"

RSpec.describe Billing::DisputeRecorder do
  let(:user) { create(:user, :trial_expired) }
  let(:sale) { create(:entitlement, user: user, starts_at: 10.days.ago, expires_at: 20.days.from_now) }

  before do
    freeze_time
    sale
  end

  def dispute(status, dispute_id: "dp_1")
    described_class.call(entitlement: sale, dispute_id: dispute_id, status: status, opened_at: 1.day.ago)
  end

  it "withholds the window while the dispute is open, keeping the sale and its dates" do
    result = dispute("open")

    expect(result.payload).to eq(entitlement: sale, changed: true)
    expect(sale.reload).to have_attributes(
      dispute_id: "dp_1", dispute_status: "open", disputed_at: 1.day.ago,
      starts_at: 10.days.ago, expires_at: 20.days.from_now, refunded_at: nil
    )
    expect(user).not_to be_paid_access
  end

  it "gives the window back when the dispute is won" do
    dispute("open")

    expect(dispute("won").payload[:changed]).to be(true)
    expect(sale.reload).to be_dispute_won
    expect(user).to be_paid_access
    expect(user.paid_access_until).to eq(20.days.from_now)
  end

  it "keeps the window withheld when the dispute is lost" do
    dispute("open")
    dispute("lost")

    expect(sale.reload).to be_dispute_lost
    expect(user).not_to be_paid_access
  end

  it "leaves a window queued behind a disputed one where it is, since the dispute can still be won" do
    queued = create(:entitlement, user: user, starts_at: 20.days.from_now, expires_at: 50.days.from_now)

    dispute("open")
    dispute("lost")

    expect(queued.reload).to have_attributes(starts_at: 20.days.from_now, expires_at: 50.days.from_now)
    expect(user.paid_access_until).to eq(50.days.from_now)
  end

  it "reports a replay as no change" do
    dispute("open")
    dispute("lost")

    expect(dispute("open").payload[:changed]).to be(false)
    expect(dispute("lost").payload[:changed]).to be(false)
  end

  it "never lets a dispute's opening, delivered late, reopen it once closed" do
    dispute("won")

    expect(dispute("open").payload[:changed]).to be(false)
    expect(sale.reload).to be_dispute_won
    expect(user).to be_paid_access
  end

  it "withholds the window again for a second dispute on the same charge" do
    dispute("won")

    dispute("open", dispute_id: "dp_2")

    expect(sale.reload).to have_attributes(dispute_id: "dp_2", dispute_status: "open")
    expect(user).not_to be_paid_access
  end
end
