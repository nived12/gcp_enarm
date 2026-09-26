require "rails_helper"

RSpec.describe SubscriptionAccess do
  describe ".free_daily_questions" do
    it "defaults to 10" do
      expect(described_class.free_daily_questions).to eq(10)
    end

    it "reads FREE_DAILY_QUESTIONS when set" do
      allow(ENV).to receive(:fetch).with("FREE_DAILY_QUESTIONS", 10).and_return("5")

      expect(described_class.free_daily_questions).to eq(5)
    end
  end

  describe "trial on create" do
    it "starts a 14-day trial" do
      user = create(:user)

      expect(user.trial_ends_at).to be_within(1.minute).of(14.days.from_now)
      expect(user).to be_active_trial
    end

    it "honours TRIAL_DURATION_DAYS" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("TRIAL_DURATION_DAYS", 14).and_return("3")

      expect(create(:user).trial_ends_at).to be_within(1.minute).of(3.days.from_now)
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
    it "is true while the grant is in the future" do
      expect(create(:user, :granted_premium)).to be_granted_premium
    end

    it "is false once the grant lapses" do
      expect(create(:user, granted_premium_until: 1.day.ago)).not_to be_granted_premium
    end

    it "is false when no grant was ever made" do
      expect(create(:user)).not_to be_granted_premium
    end
  end

  describe "#active_paid_subscription?" do
    # Pay lands in Phase 6. Until then the granted-premium list is the only paid path,
    # and this spec is what will fail loudly if that assumption is ever quietly broken.
    it "is true for a granted user and false for everyone else" do
      expect(create(:user, :granted_premium)).to be_active_paid_subscription
      expect(create(:user, :trial_expired)).not_to be_active_paid_subscription
    end
  end

  describe "#subscription_access_result" do
    it "allows a user on an active trial" do
      expect(create(:user).subscription_access_result).to eq({ allowed: true })
    end

    it "allows a granted-premium user whose trial has lapsed" do
      user = create(:user, :granted_premium, :trial_expired)

      expect(user.subscription_access_result).to eq({ allowed: true })
    end

    it "allows a free user who is still under the daily cap" do
      user = create(:user, :trial_expired)

      expect(user.subscription_access_result).to eq({ allowed: true })
    end

    it "denies a free user who has spent the daily allowance" do
      user = create(:user, :trial_expired)
      allow(user).to receive(:questions_answered_today).and_return(10)

      result = user.subscription_access_result

      expect(result[:allowed]).to be(false)
      expect(result[:reason]).to eq(:daily_limit_reached)
      expect(result[:message]).to eq(I18n.t("exams.denied.daily_limit_reached", limit: 10))
    end

    it "counts the student's own calendar day, which ends at midnight where they are" do
      user = create(:user, :trial_expired, time_zone: "America/Tijuana")
      kase = create(:published_case, questions_count: 3)
      exam = create(:exam, user: user)
      answer_at = lambda do |position, time|
        exam.exam_questions.create!(question: kase.questions[position], clinical_case: kase, position: position + 1)
            .create_answer!(answered_at: time)
      end
      zone = Time.find_zone("America/Tijuana")
      # Ended well before the dates travelled to; the trait's "a day ago" is relative to
      # the real clock and put these dates back inside the trial once it passed them.
      user.update_column(:trial_ends_at, zone.local(2026, 9, 1))
      answer_at.call(0, zone.local(2026, 9, 22, 23, 59))
      answer_at.call(1, zone.local(2026, 9, 23, 8))
      answer_at.call(2, zone.local(2026, 9, 23, 22))
      allow(SubscriptionAccess).to receive(:free_daily_questions).and_return(2)

      travel_to(zone.local(2026, 9, 23, 23, 59)) { expect(user.subscription_access_result[:allowed]).to be(false) }
      travel_to(zone.local(2026, 9, 24, 0, 0)) { expect(user.subscription_access_result[:allowed]).to be(true) }
    end

    it "takes the message from the scope the caller names" do
      user = create(:user, :trial_expired)
      allow(user).to receive(:questions_answered_today).and_return(10)
      allow(I18n).to receive(:t).and_call_original

      user.subscription_access_result(i18n_scope: "otro.scope")

      expect(I18n).to have_received(:t).with("otro.scope.daily_limit_reached", limit: 10)
    end
  end

  describe "#daily_questions_limit" do
    it "is nil — uncapped — for trial and granted users" do
      expect(create(:user).daily_questions_limit).to be_nil
      expect(create(:user, :granted_premium, :trial_expired).daily_questions_limit).to be_nil
    end

    it "is nil for admins and reviewers, with no trial and no granted date" do
      expect(create(:user, :admin, :trial_expired).daily_questions_limit).to be_nil
      expect(create(:user, :trial_expired, role: :reviewer).daily_questions_limit).to be_nil
    end

    it "is the free allowance once the trial lapses" do
      expect(create(:user, :trial_expired).daily_questions_limit).to eq(10)
    end
  end

  describe "paid windows" do
    let(:user) { create(:user, :trial_expired) }

    it "lift the cap while one is open, and only then" do
      freeze_time
      create(:entitlement, user: user, starts_at: 2.months.ago, expires_at: 1.month.ago)
      expect(user).not_to be_paid_access
      expect(user.daily_questions_limit).to eq(10)

      create(:entitlement, user: user, starts_at: 1.day.ago, expires_at: 1.month.from_now)
      expect(user).to be_paid_access
      expect(user).to be_active_paid_subscription
      expect(user.daily_questions_limit).to be_nil
    end

    it "run to the end of the last stacked window" do
      freeze_time
      create(:entitlement, user: user, starts_at: 1.day.ago, expires_at: 1.month.from_now)
      create(:entitlement, user: user, starts_at: 1.month.from_now, expires_at: 4.months.from_now)

      expect(user.paid_access_until).to eq(4.months.from_now)
    end

    it "have no end date when none was bought" do
      expect(user.paid_access_until).to be_nil
    end
  end
end
