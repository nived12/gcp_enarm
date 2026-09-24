require "rails_helper"

RSpec.describe LandingHelper, type: :helper do
  describe "#bank_count" do
    it "rounds down to two significant figures and says there are more" do
      expect([83, 179, 427, 4_580, 10_432].map { |count| helper.bank_count(count) })
        .to eq(["80+", "170+", "420+", "4,500+", "10,000+"])
    end

    it "keeps an exact round number, and a single digit, as they are" do
      expect([7, 80, 4_500].map { |count| helper.bank_count(count) }).to eq(["7", "80", "4,500"])
    end
  end
end
