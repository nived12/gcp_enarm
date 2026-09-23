require "rails_helper"

RSpec.describe Pearls::ReviewRecorder do
  let(:user) { create(:user) }
  let(:recommendation) { create(:recommendation) }

  def grade(value)
    described_class.call(user, recommendation, grade: value)
  end

  it "schedules the pearl by the student's own grade and counts it towards today" do
    card = grade("again").payload[:card]

    expect(card).to have_attributes(persisted?: true, lapses: 1, due_on: user.study_date + 1)
    expect(user.study_days.sole.pearls_reviewed).to eq(1)
  end

  it "grades a pearl once a day, however many times it is sent" do
    grade("easy")
    grade("again")

    expect(ReviewCard.sole).to have_attributes(reviews_count: 1, lapses: 0)
    expect(user.study_days.sole.pearls_reviewed).to eq(1)
  end

  it "refuses a grade the buttons never send" do
    result = grade("perfect")

    expect(result.errors.full_messages).to eq([I18n.t("pearls.unknown_grade")])
    expect(ReviewCard.count).to eq(0)
  end
end
