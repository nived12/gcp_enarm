require "rails_helper"

RSpec.describe AnswerOption do
  it "keeps positions unique within a question" do
    option = create(:answer_option, position: 1)

    expect(build(:answer_option, question: option.question, position: 1)).not_to be_valid
  end

  describe ".correct" do
    it "returns only the correct option" do
      question = create(:question)
      create(:answer_option, question: question, position: 1, correct: false)
      correct = create(:answer_option, question: question, position: 2, correct: true)

      expect(question.answer_options.correct).to contain_exactly(correct)
    end
  end
end
