require "rails_helper"

RSpec.describe Plan do
  it "sells the four prepaid windows at the owner's prices, in pesos" do
    expect(described_class.all.map { |plan| [plan.code, plan.months, plan.price] }).to eq(
      [["one_month", 1, 199], ["three_months", 3, 449], ["six_months", 6, 749], ["twelve_months", 12, 1_099]]
    )
    expect(described_class.all.map(&:currency).uniq).to eq(["MXN"])
  end

  it "finds a plan by its code, and nothing for an unknown one" do
    expect(described_class.find(:six_months)).to have_attributes(code: "six_months", months: 6)
    expect(described_class.find("forever")).to be_nil
  end

  it "rounds the monthly equivalent to whole pesos" do
    expect(described_class.all.map(&:monthly_price)).to eq([199, 150, 125, 92])
  end

  it "rounds the daily equivalent to whole pesos, on an average month" do
    expect(described_class.all.map(&:daily_price)).to eq([7, 5, 4, 3])
  end

  it "states the charge in the currency's minor unit" do
    expect(described_class.find("twelve_months").amount_in_cents).to eq(109_900)
  end
end
