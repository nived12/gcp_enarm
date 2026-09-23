require "rails_helper"

RSpec.describe Stats::StreakCalculator do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 9, 23) }

  def studied(*days_ago, questions: StudyDay::MINIMUM_QUESTIONS)
    days_ago.each { |ago| user.study_days.create!(date: today - ago, questions_answered: questions) }
  end

  def streak
    described_class.call(user, today: today).payload
  end

  it "is nothing at all before the first study day" do
    expect(streak).to have_attributes(
      current: 0, best: 0, freezes: 0, frozen_dates: [], today_questions: 0,
      today_done: false
    )
    expect(streak.today_remaining).to eq(10)
  end

  it "counts consecutive days, today included once it reaches the minimum" do
    studied(2, 1, 0)

    expect(streak).to have_attributes(current: 3, best: 3, today_done: true, today_questions: 10)
    expect(streak.today_remaining).to eq(0)
  end

  it "keeps yesterday's streak alive while today still has time left" do
    studied(2, 1)
    studied(0, questions: 4)

    expect(streak).to have_attributes(current: 2, today_done: false, today_questions: 4)
    expect(streak.today_remaining).to eq(6)
  end

  it "does not count a day below the minimum" do
    studied(2, 0)
    studied(1, questions: 9)

    expect(streak).to have_attributes(current: 1, best: 1)
  end

  it "ends quietly after a missed day with nothing banked, and keeps the best" do
    studied(5, 4, 3, 1, 0)

    expect(streak).to have_attributes(current: 2, best: 3, frozen_dates: [])
  end

  it "ends when the last studied day is more than a day behind" do
    studied(4, 3, 2)

    expect(streak).to have_attributes(current: 0, best: 3)
  end

  it "earns a freeze on the seventh day and spends it on the next missed one" do
    studied(*(2..8).to_a)
    expect(streak).to have_attributes(current: 7, freezes: 0, frozen_dates: [today - 1])

    studied(0)
    expect(streak).to have_attributes(current: 8, frozen_dates: [today - 1])
  end

  it "banks at most two freezes, so three missed days end even a long streak" do
    studied(*(4..24).to_a)

    expect(streak).to have_attributes(current: 0, best: 21, freezes: 0, frozen_dates: [])
  end

  it "spends both banked freezes on two missed days in a row, then earns the next" do
    studied(*(5..24).to_a, 2, 1, 0)

    expect(streak).to have_attributes(current: 23, freezes: 1, frozen_dates: [today - 4, today - 3])
  end
end
