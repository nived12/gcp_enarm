require "rails_helper"

RSpec.describe Exams::WeakSpotBuilder do
  let(:user) { create(:user) }
  let(:weak) { create(:topic) }
  let(:weaker) { create(:topic) }
  let(:strong) { create(:topic) }

  def build(seed: 1)
    described_class.call(user: user, mode: "weak_spots", random: Random.new(seed))
  end

  def answer(topic, outcome)
    create(:published_case, topic: topic, questions_count: 1).tap { |kase| sit(user, kase, [outcome]) }
  end

  it "has nothing to build before the student has weak spots" do
    result = build

    expect(result.errors.full_messages).to eq([I18n.t("weak_spots.none")])
  end

  context "with a history" do
    before do
      3.times { answer(weaker, [:wrong, "did_not_know"]) }
      answer(weaker, :right)
      2.times { answer(weak, [:wrong, "did_not_know"]) }
      2.times { answer(weak, :right) }
      6.times { answer(strong, :right) }
    end

    it "draws only from the weak topics, and records which" do
      exam = build.payload[:exam]

      expect(exam.exam_questions.map { |eq| eq.clinical_case.topic }.uniq).to contain_exactly(weak, weaker)
      expect(exam.filters).to eq("interleave" => true, "topic_ids" => [weaker.id, weak.id])
      expect(exam).to have_attributes(mode: "weak_spots", feedback_timing: "after_each")
    end

    it "gives the weakest topic the most seats, and new cases before missed and known ones" do
      fresh = Array.new(3) { create(:published_case, topic: weaker, questions_count: 1) }
      create(:published_case, topic: weak, questions_count: 1)

      order = build.payload[:exam].exam_questions.map(&:clinical_case)
      in_weaker = order.select { |kase| kase.topic == weaker }

      expect(in_weaker.first(3)).to match_array(fresh)
      expect(in_weaker.last.questions.first.id).to eq(
        ExamQuestion.joins(:answer).where(answers: { correct: true }, clinical_case: in_weaker).pick(:question_id)
      )
      expect(order.first.topic).to eq(weaker)
      expect(in_weaker.size).to be > order.count { |kase| kase.topic == weak }
    end
  end
end
