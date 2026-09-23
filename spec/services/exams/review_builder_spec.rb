require "rails_helper"

RSpec.describe Exams::ReviewBuilder do
  let(:user) { create(:user) }

  def build
    described_class.call(user: user, mode: "review")
  end

  it "has nothing to build when nothing is due" do
    sit(user, create(:published_case), %i[wrong wrong])

    result = build

    expect(result).to be_failure
    expect(result.errors.full_messages).to eq([I18n.t("reviews.nothing_due")])
  end

  it "draws the published cases due today, most overdue first, as a practice session" do
    older, newer, withdrawn, later = create_list(:published_case, 4, questions_count: 2)
    travel_to(3.days.ago) { sit(user, older, %i[wrong right]) }
    travel_to(2.days.ago) { sit(user, newer, %i[wrong right]) }
    travel_to(2.days.ago) { sit(user, withdrawn, %i[wrong right]) }
    sit(user, later, %i[wrong right])
    withdrawn.update!(status: "retired")

    exam = build.payload[:exam]

    expect(exam.exam_questions.map(&:clinical_case).uniq).to eq([older, newer])
    expect(exam).to have_attributes(
      mode: "review", question_count: 4, feedback_timing: "after_each",
      time_limit_seconds: nil
    )
  end

  it "stops at a session's length and leaves the rest for the next one" do
    cases = create_list(:published_case, 12, questions_count: 2)
    travel_to(1.day.ago) { cases.each { |kase| sit(user, kase, %i[wrong wrong]) } }

    expect(build.payload[:exam].question_count).to eq(Exam::QUESTION_COUNTS["review"])
  end
end
