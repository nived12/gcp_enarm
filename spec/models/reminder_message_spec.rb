require "rails_helper"

RSpec.describe ReminderMessage do
  let(:date) { Date.new(2026, 10, 6) }
  let(:plan) { create(:study_plan, starts_on: date - 30, exam_date: date + 7) }
  let(:topics) { create_list(:topic, 2) }
  let(:plan_day) do
    create(:study_plan_day, study_plan: plan, date: date).tap do |day|
      topics.each_with_index { |topic, index| day.day_topics.create!(topic: topic, position: index + 1) }
    end
  end

  def streak(current)
    Stats::StreakCalculator::Result.new(
      current: current, best: current, freezes: 0, frozen_dates: [], today_questions: 0, today_done: false
    )
  end

  def message(*kinds, current: 0)
    described_class.new(kinds: kinds, date: date, plan: plan, plan_day: plan_day, streak: streak(current))
  end

  it "names the day's topics and opens the day" do
    built = message("study_day")

    expect(built.title).to eq(I18n.t("reminders.message.study_day.title"))
    expect(built.lines).to eq([I18n.t("reminders.message.study_day.body", day: topics.map(&:name).join(" · "))])
    expect(built.path).to eq("/study_plan/days/2026-10-06")
  end

  it "mentions a running streak alongside the plan" do
    expect(message("study_day", current: 4).lines.last).to eq(I18n.t("reminders.message.study_day.streak", count: 4))
  end

  it "counts the streak in the nudge and sends the student home, where the quiz starts" do
    built = message("streak_at_risk", current: 12)

    expect(built.title).to eq(I18n.t("reminders.message.streak_at_risk.title", count: 12))
    expect(built.lines).to eq([I18n.t("reminders.message.streak_at_risk.body", minimum: StudyDay::MINIMUM_QUESTIONS)])
    expect(built.path).to eq("/")
  end

  it "counts down to the exam and opens the calendar" do
    built = message("exam_countdown")

    expect(built.title).to eq(I18n.t("reminders.message.exam_countdown.title", count: 7))
    expect(built.lines).to eq([I18n.t("reminders.message.exam_countdown.body.days_7")])
    expect(built.path).to eq("/study_plan")
  end

  it "reads as one message when the countdown and the day's plan fall together" do
    built = message("exam_countdown", "study_day").to_h

    expect(built[:title]).to eq(I18n.t("reminders.message.exam_countdown.title", count: 7))
    expect(built[:lines].size).to eq(2)
    expect(built[:path]).to eq("/study_plan/days/2026-10-06")
  end
end
