require "rails_helper"

RSpec.describe Entitlement do
  it "refuses a window that ends before it starts" do
    entitlement = build(:entitlement, starts_at: Time.current, expires_at: 1.day.ago)

    expect(entitlement).not_to be_valid
    expect(entitlement.errors[:expires_at]).to be_present
  end

  it "records a provider's purchase once" do
    create(:entitlement, external_id: "cs_1")

    expect(build(:entitlement, external_id: "cs_1")).not_to be_valid
    expect(build(:entitlement, external_id: "cs_1", source: "apple")).to be_valid
  end

  it "knows which windows are open at a moment and which have not yet ended" do
    freeze_time
    past = create(:entitlement, starts_at: 2.months.ago, expires_at: 1.month.ago)
    current = create(:entitlement, starts_at: 1.day.ago, expires_at: 1.month.from_now)
    upcoming = create(:entitlement, starts_at: 1.month.from_now, expires_at: 2.months.from_now)

    expect(described_class.active_at(Time.current)).to eq([current])
    expect(described_class.unexpired).to contain_exactly(current, upcoming)
    expect(described_class.recent.first).to eq(upcoming)
    expect(past.catalog_plan).to eq(Plan.find("one_month"))
  end
end
