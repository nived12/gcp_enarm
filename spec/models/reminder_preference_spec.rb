require "rails_helper"

RSpec.describe ReminderPreference do
  it "starts with every reminder off" do
    preference = described_class.new

    expect(preference.any_reminder?).to be(false)
    expect(preference.by_email).to be(false)
  end

  it "accepts only the half hours the form offers" do
    expect(build(:reminder_preference, minute_of_day: 19 * 60 + 30)).to be_valid
    expect(build(:reminder_preference, minute_of_day: 19 * 60 + 15)).not_to be_valid
    expect(build(:reminder_preference, minute_of_day: 3 * 60)).not_to be_valid
  end

  it "finds the students who want any reminder at all" do
    wants = %i[study_days streak_at_risk exam_countdown].map { |rule| create(:reminder_preference, rule => true) }
    create(:reminder_preference, by_email: true)

    expect(described_class.wanting_any).to match_array(wants)
  end

  describe ".due_at?" do
    let(:zone) { ActiveSupport::TimeZone["America/Mexico_City"] }

    it "is due from the chosen minute for one hour" do
      expect(described_class.due_at?(480, zone.local(2026, 10, 6, 7, 59))).to be(false)
      expect(described_class.due_at?(480, zone.local(2026, 10, 6, 8, 0))).to be(true)
      expect(described_class.due_at?(480, zone.local(2026, 10, 6, 8, 59))).to be(true)
      expect(described_class.due_at?(480, zone.local(2026, 10, 6, 9, 0))).to be(false)
    end
  end
end
