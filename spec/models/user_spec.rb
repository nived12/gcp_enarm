require "rails_helper"

RSpec.describe User do
  describe "normalization and validation" do
    it "downcases and strips the email address" do
      user = create(:user, email_address: "  Gabriela@Example.COM ")

      expect(user.email_address).to eq("gabriela@example.com")
    end

    it "rejects an unsupported locale" do
      user = build(:user, locale: "fr")

      expect(user).not_to be_valid
    end
  end

  describe "#active_trial?" do
    it "is true for a freshly created user" do
      expect(create(:user)).to be_active_trial
    end

    it "is false once the trial has passed" do
      expect(create(:user, :trial_expired)).not_to be_active_trial
    end
  end

  describe "#granted_premium?" do
    it "is false by default" do
      expect(create(:user)).not_to be_granted_premium
    end

    it "is true while the grant is live" do
      expect(create(:user, :granted_premium)).to be_granted_premium
    end

    it "is false once the grant has lapsed" do
      user = create(:user, granted_premium_until: 1.day.ago)

      expect(user).not_to be_granted_premium
    end
  end

  describe "#subscription_access_result" do
    it "allows a granted-premium user whose trial has expired" do
      user = create(:user, :granted_premium, :trial_expired)

      expect(user.subscription_access_result[:allowed]).to be(true)
    end

    it "reports no cap for a granted-premium user" do
      expect(create(:user, :granted_premium).daily_questions_limit).to be_nil
    end

    it "caps a user with neither trial nor grant" do
      user = create(:user, :trial_expired)

      expect(user.daily_questions_limit).to eq(SubscriptionAccess.free_daily_questions)
    end
  end
end
