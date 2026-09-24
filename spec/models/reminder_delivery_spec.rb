require "rails_helper"

RSpec.describe ReminderDelivery do
  let(:user) { create(:user) }
  let(:date) { Date.new(2026, 10, 6) }

  def claim(kind, on: date)
    described_class.claim(user: user, local_date: on, kind: kind, channels: ["email"])
  end

  it "lets a kind be claimed once a day" do
    expect(claim("study_day")).to be(true)
    expect(claim("study_day")).to be(false)
    expect(claim("study_day", on: date + 1)).to be(true)
  end

  it "shares the daily slot between the study reminder and the streak nudge" do
    expect(claim("study_day")).to be(true)
    expect(claim("streak_at_risk")).to be(false)
  end

  it "gives the countdown a slot of its own" do
    claim("study_day")

    expect(claim("exam_countdown")).to be(true)
    expect(described_class.last).to have_attributes(slot: "countdown", channels: ["email"])
  end
end
