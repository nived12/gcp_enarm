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

  describe "a case counted where it happens as well as by what it is about" do
    let(:emergency) { empty_area }

    it "holds a troncal's case in the area it is set in too" do
      set_in_family = internal_cases.first(3)
      set_in_family.each { |kase| kase.update!(setting: family) }
      sit(set_in_family.first(1))

      family_area = coverage.areas.find { |area| area.specialty == family }
      expect(family_area).to have_attributes(seen: 1, published: 7)
      expect(coverage.areas.first).to have_attributes(seen: 1, published: 12)
    end

    it "counts the whole bank by case, so a case in two areas is one case" do
      internal_cases.each { |kase| kase.update!(setting: family) }
      sit(internal_cases.first(2))

      expect(coverage).to have_attributes(seen: 2, published: 16)
    end

    it "counts a case about Urgencias set in urgencias once in Urgencias" do
      kase = create(:published_case, specialty: emergency, setting: emergency, questions_count: 1)
      sit([kase])

      expect(coverage.areas.find { |area| area.specialty == emergency }).to have_attributes(seen: 1, published: 1)
    end

    it "names a transversal area neglected when the cases set in it go unseen" do
      internal_cases.last(6).each { |kase| kase.update!(setting: emergency) }
      sit(internal_cases.first(6) + family_cases)

      expect(coverage.neglected.map(&:specialty)).to eq([emergency])
    end
  end

  # Before settings existed, Medicina Familiar held no case at all and a student was told
  # to go and study it.
  it "never names an area with nothing published as neglected" do
    sit(internal_cases + family_cases.first(1))

    expect(coverage.areas.last).to be_empty
    expect(coverage.neglected.map(&:specialty)).not_to include(empty_area)
  end

  it "has no share and nothing to name while the bank is empty" do
    ClinicalCase.update_all(status: "draft")

    expect(coverage).to have_attributes(seen: 0, published: 0, share: nil, neglected: [])
  end
end
