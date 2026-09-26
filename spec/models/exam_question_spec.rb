require "rails_helper"

RSpec.describe ExamQuestion do
  describe "#answer_options" do
    let(:kase) { create(:published_case, questions_count: 1) }
    let(:question) { kase.questions.sole }

    def place(exam, position = 1)
      described_class.create!(exam: exam, question: question, clinical_case: kase, position: position)
    end

    it "shows every option of the question, once" do
      shown = place(create(:exam)).answer_options

      expect(shown).to match_array(question.answer_options)
    end

    it "keeps the same order for the same row, across reloads" do
      row = place(create(:exam))

      expect(described_class.find(row.id).answer_options.map(&:id)).to eq(row.answer_options.map(&:id))
    end

    it "does not always put the correct answer where the model wrote it" do
      spots = Array.new(12) { place(create(:exam)).answer_options.index(&:correct?) }

      expect(spots.uniq.size).to be > 1
    end
  end
end
