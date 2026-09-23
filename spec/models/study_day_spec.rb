require "rails_helper"

RSpec.describe StudyDay do
  let(:user) { create(:user) }

  describe ".date_for" do
    it "keeps the small hours on the day before, until 4 a.m. where the student is" do
      zone = "America/Mexico_City"

      expect(
        described_class.date_for(
          Time.find_zone(zone).local(2026, 9, 23, 3, 59),
          zone
        )
      ).to eq(Date.new(2026, 9, 22))
      expect(described_class.date_for(Time.find_zone(zone).local(2026, 9, 23, 4, 0), zone)).to eq(Date.new(2026, 9, 23))
    end

    it "reads the clock of the student's own zone, not the server's" do
      instant = Time.utc(2026, 9, 23, 10, 30)

      expect(described_class.date_for(instant, "America/Mexico_City")).to eq(Date.new(2026, 9, 23))
      expect(described_class.date_for(instant, "America/Tijuana")).to eq(Date.new(2026, 9, 22))
    end
  end

  describe ".time_range" do
    it "runs from the day's 4 a.m. to the next one, in the student's zone" do
      range = described_class.time_range(Date.new(2026, 9, 23), "America/Cancun")

      expect(range).to eq(Time.utc(2026, 9, 23, 9)...Time.utc(2026, 9, 24, 9))
      expect([range.begin, range.end - 1.second].map { |time| described_class.date_for(time, "America/Cancun") })
        .to eq([Date.new(2026, 9, 23)] * 2)
    end

    it "keeps both ends at 4 a.m. across a change of clocks" do
      zone = "America/Tijuana"
      range = described_class.time_range(Date.new(2026, 3, 7), zone)

      expect(range.end - range.begin).to eq(23.hours)
      expect(described_class.date_for(range.end, zone)).to eq(Date.new(2026, 3, 8))
      expect(described_class.date_for(range.end - 1.second, zone)).to eq(Date.new(2026, 3, 7))
    end
  end

  describe ".qualifies?" do
    it "takes ten questions, or one whole pearls session of ten cards" do
      expect(described_class.qualifies?(9, 0)).to be(false)
      expect(described_class.qualifies?(10, 0)).to be(true)
      expect(described_class.qualifies?(0, 9)).to be(false)
      expect(described_class.qualifies?(0, 10)).to be(true)
    end
  end

  describe ".count_answer!" do
    it "starts the day's row and adds to it after that" do
      at = Time.zone.local(2026, 9, 23, 12)

      2.times { described_class.count_answer!(user, at: at) }
      described_class.count_answer!(user, at: at + 1.day)

      expect(user.study_days.order(:date).pluck(:date, :questions_answered))
        .to eq([[Date.new(2026, 9, 23), 2], [Date.new(2026, 9, 24), 1]])
    end
  end

  describe ".count_pearl!" do
    it "counts pearls on the same day row as answers, without touching the answers" do
      at = Time.zone.local(2026, 9, 23, 12)

      described_class.count_answer!(user, at: at)
      2.times { described_class.count_pearl!(user, at: at) }

      expect(user.study_days.pluck(:questions_answered, :pearls_reviewed)).to eq([[1, 2]])
    end
  end

  describe "the student's calendar" do
    it "is kept in a real time zone, since Mexico has several" do
      expect(build(:user, time_zone: "America/Hermosillo")).to be_valid
      expect(build(:user, time_zone: "Mexico/Nowhere")).not_to be_valid
    end

    it "gives the day the student is on" do
      user.update!(time_zone: "America/Cancun")

      expect(user.study_date(Time.utc(2026, 9, 23, 9, 0))).to eq(Date.new(2026, 9, 23))
      expect(user.study_date(Time.utc(2026, 9, 23, 8, 59))).to eq(Date.new(2026, 9, 22))
    end
  end
end
