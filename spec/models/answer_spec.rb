require "rails_helper"

RSpec.describe Answer do
  let(:exam) { create(:exam) }
  let(:kase) { create(:published_case, questions_count: 1) }
  let(:exam_question) { exam.exam_questions.create!(question: kase.questions.first, clinical_case: kase, position: 1) }

  it "only accepts an option of its own question" do
    stranger = create(:answer_option)

    answer = exam_question.build_answer(answer_option: stranger, answered_at: Time.current)

    expect(answer).not_to be_valid
    expect(answer.errors.of_kind?(:answer_option, :invalid)).to be(true)
  end

  it "cannot hold an option without the exam question it answers" do
    answer = described_class.new(answer_option: create(:answer_option), answered_at: Time.current)

    expect(answer).not_to be_valid
  end

  it "takes the student's reason only from the four the interface offers" do
    answer = exam_question.create_answer!(answered_at: Time.current)

    answer.error_reason = "guessed"

    expect(answer).not_to be_valid
  end

  it "counts the answers given on a day" do
    exam_question.create_answer!(answered_at: Time.current)

    expect(
      [described_class.answered_on(Date.current).count,
      described_class.answered_on(Date.yesterday).count]
    ).to eq([1, 0])
  end
end
