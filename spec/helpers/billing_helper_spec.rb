require "rails_helper"

RSpec.describe BillingHelper, type: :helper do
  it "writes pesos the Mexican way, without cents when there are none" do
    expect(helper.money(1_099)).to eq("$1,099")
    expect(helper.money(BigDecimal("449.00"))).to eq("$449")
    expect(helper.money(BigDecimal("12.5"))).to eq("$12.50")
  end
end
