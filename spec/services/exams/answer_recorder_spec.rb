require "rails_helper"

RSpec.describe Exams::AnswerRecorder do
  let(:user) { create(:user) }
  let(:kase) { create(:published_case, questions_count: 2) }
  let(:exam) { create(:exam, user: user, question_count: 2, running_since: Time.current) }
  let!(:first) { exam.exam_questions.create!(question: kase.questions.first, clinical_case: kase, position: 1) }
  let!(:second) { exam.exam_questions.create!(question: kase.questions.second, clinical_case: kase, position: 2) }

  def option(exam_question, text)
    exam_question.question.answer_options.find_by!(text: text)
  end

  def record(exam_question, text)
    described_class.call(exam_question, answer_option_id: option(exam_question, text).id)
  end

  it "keeps the choice and whether it was right, as it stood when answered" do
    answer = record(first, "Troponina I").payload[:answer]

    expect(answer).to have_attributes(correct: false, answer_option: option(first, "Troponina I"), error_reason: nil)
    expect(record(second, "Electrocardiograma de 12 derivaciones").payload[:answer]).to be_correct
  end

  it "bills each question the exam-clock seconds since the previous answer" do
    freeze_time
    exam.update!(running_since: Time.current)

    travel 40.seconds
    record(first, "Troponina I")
    travel 25.seconds
    record(second, "Troponina I")

    expect(exam.answers.order(:id).pluck(:seconds_spent)).to eq([40, 25])
  end

  it "only takes the question the student is on" do
    result = record(second, "Troponina I")

    expect(result.errors.full_messages).to eq([I18n.t("exams.answers.not_current")])
  end

  it "needs an option of this question" do
    result = described_class.call(first, answer_option_id: create(:answer_option).id)

    expect(result.errors.full_messages).to eq([I18n.t("exams.answers.choose_option")])
  end

  it "takes nothing while the exam is paused" do
    exam.pause!

    expect(record(first, "Troponina I").errors.full_messages).to eq([I18n.t("exams.answers.not_running")])
  end

  it "ends the exam when the answer arrives after the clock ran out, and does not count it" do
    exam.update!(mode: "full_exam", time_limit_seconds: 120, running_since: 121.seconds.ago)

    result = record(first, "Electrocardiograma de 12 derivaciones")

    expect(result.errors.full_messages).to eq([I18n.t("exams.answers.time_up")])
    expect(exam.reload).to have_attributes(status: "completed", score: 0)
    expect(Answer.count).to eq(0)
  end

  it "stops at the free daily allowance" do
    user.update_column(:trial_ends_at, 1.day.ago)
    allow(SubscriptionAccess).to receive(:free_daily_questions).and_return(1)
    record(first, "Troponina I")

    result = record(second, "Troponina I")

    expect(result.errors.full_messages).to eq([I18n.t("exams.denied.daily_limit_reached", limit: 1)])
  end

  describe "on the single page" do
    before { exam.update!(feedback_timing: "at_end") }

    it "answers in any order and lets the student change their mind until the end" do
      record(second, "Troponina I")
      record(second, "Electrocardiograma de 12 derivaciones")

      expect(second.reload.answer).to have_attributes(
        correct: true,
        answer_option: option(second, "Electrocardiograma de 12 derivaciones")
      )
      expect(Answer.count).to eq(1)
    end

    it "does not spend the daily allowance on a changed answer" do
      user.update_column(:trial_ends_at, 1.day.ago)
      allow(SubscriptionAccess).to receive(:free_daily_questions).and_return(1)
      record(first, "Troponina I")

      expect(record(first, "Ecocardiograma")).to be_success
      expect(record(second, "Troponina I")).to be_failure
    end
  end

  describe "the study day" do
    it "counts each new answer on the student's own calendar, a changed one only once" do
      exam.update!(feedback_timing: "at_end")

      record(first, "Troponina I")
      record(first, "Ecocardiograma")
      record(second, "Troponina I")

      expect(user.study_days.pluck(:date, :questions_answered)).to eq([[user.study_date, 2]])
    end

    it "is not counted when the answer is not saved" do
      exam.pause!
      record(first, "Troponina I")

      expect(StudyDay.count).to eq(0)
    end

    it "keeps the answer and the count together, so neither is written alone" do
      allow(StudyDay).to receive(:count_answer!).and_raise(ActiveRecord::StatementInvalid)

      expect { record(first, "Troponina I") }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Answer.count).to eq(0)
    end
  end
end
