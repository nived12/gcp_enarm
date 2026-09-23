require "rails_helper"

RSpec.describe Stats::CoverageCalculator do
  let(:user) { create(:user) }
  let(:internal) { create(:specialty, name: "Medicina Interna", position: 1) }
  let(:family) { create(:specialty, name: "Medicina Familiar", kind: "cross_cutting", position: 2) }
  let!(:empty_area) { create(:specialty, name: "Urgencias", kind: "cross_cutting", position: 3) }
  let!(:internal_cases) { create_list(:published_case, 12, specialty: internal, questions_count: 1) }
  let!(:family_cases) { create_list(:published_case, 4, specialty: family, questions_count: 1) }

  # Each case is put in one exam; only the answered ones have been seen.
  def sit(answered, drawn: [], status: "completed")
    exam = create(:exam, user: user, question_count: answered.size + drawn.size, status: status)
    (answered + drawn).each.with_index(1) do |kase, position|
      exam_question = exam.exam_questions.create!(
        question: kase.questions.first, clinical_case: kase,
        position: position
      )
      exam_question.create_answer!(correct: false, answered_at: Time.current) if answered.include?(kase)
    end
  end

  def coverage
    described_class.call(user).payload
  end

  it "measures every area against its published cases, the transversal ones included" do
    create(:clinical_case, specialty: family, status: "draft")
    sit(internal_cases.first(3), drawn: family_cases.first(2))

    expect(coverage.areas.map { |area| [area.specialty, area.seen, area.published] })
      .to eq([[internal, 3, 12], [family, 0, 4], [empty_area, 0, 0]])
    expect(coverage.areas.first.share).to eq(25)
    expect(coverage.areas.last.share).to be_nil
    expect(coverage).to have_attributes(seen: 3, published: 16)
    expect(coverage.share).to be_within(0.01).of(18.75)
  end

  it "counts a case seen once it was answered, even in an exam later discarded" do
    sit(internal_cases.first(1), status: "discarded")

    expect(coverage.seen).to eq(1)
  end

  it "names the areas left far behind the rest, least seen first, once there is a pattern" do
    sit(internal_cases.first(9))
    expect(coverage.neglected).to eq([])

    sit(internal_cases.last(1))
    expect(coverage.neglected.map(&:specialty)).to eq([family])
  end

  it "has no share and nothing to name while the bank is empty" do
    ClinicalCase.update_all(status: "draft")

    expect(coverage).to have_attributes(seen: 0, published: 0, share: nil, neglected: [])
  end
end
