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

  describe "the rationale a student sees" do
    def option(**attributes)
      build(:answer_option, rationale: "No es el estudio inicial.", **attributes)
    end

    it "shows a distractor's rationale that is sound or not yet judged" do
      expect(option).to be_rationale_visible
      expect(option(rationale_verdict: "sound")).to be_rationale_visible
    end

    it "hides one the second opinion rejected, and never shows one on the correct option or an empty one" do
      expect(option(rationale_verdict: "overstated")).not_to be_rationale_visible
      expect(option(rationale_verdict: "contradicted")).to be_rationale_rejected
      expect(option(correct: true)).not_to be_rationale_visible
      expect(option(rationale: nil)).not_to be_rationale_visible
    end

    it "finds the rationales still to judge and the ones to write again" do
      unjudged = create(:answer_option, rationale: "Razón.")
      rejected = create(:answer_option, rationale: "Razón.", rationale_verdict: "overstated")
      create(:answer_option, rationale: "Razón.", rationale_verdict: "sound")
      create(:answer_option, rationale: nil)

      expect(described_class.rationale_unjudged).to contain_exactly(unjudged)
      expect(described_class.rationale_rejected).to contain_exactly(rejected)
    end
  end
end
