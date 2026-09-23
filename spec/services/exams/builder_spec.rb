require "rails_helper"

RSpec.describe Exams::Builder do
  let(:user) { create(:user) }
  let(:internal) { create(:specialty, name: "Medicina Interna", position: 1) }
  let(:pediatrics) { create(:specialty, name: "Pediatría", position: 2) }

  def build(mode: "custom", filters: {}, seed: 1)
    described_class.call(user: user, mode: mode, filters: filters, random: Random.new(seed))
  end

  def cases_in(exam)
    exam.exam_questions.map(&:clinical_case).uniq
  end

  it "draws only published cases — never a draft, an unsupported or a withdrawn one" do
    live = create(:published_case)
    create(:clinical_case, verification_verdict: "supported")
    create(:clinical_case, verification_verdict: "supported", status: "retired")

    exam = build.payload[:exam]

    expect(cases_in(exam)).to eq([live])
  end

  it "takes whole cases, in their own question order, and records how many questions it drew" do
    kase = create(:published_case, questions_count: 3)

    exam = build(mode: "quick_quiz").payload[:exam]

    expect(exam.exam_questions.map(&:question)).to eq(kase.questions.to_a)
    expect(exam).to have_attributes(
      question_count: 3, mode: "quick_quiz", time_limit_seconds: nil,
      filters: { "interleave" => true }
    )
    expect(exam.exam_questions.map(&:position)).to eq([1, 2, 3])
  end

  it "stops adding cases once the target is met, overshooting rather than splitting a case" do
    4.times { create(:published_case, questions_count: 3) }

    exam = build(filters: { question_count: 5 }).payload[:exam]

    expect(exam.question_count).to eq(6)
  end

  it "gives the exam-length modes the real exam's conditions unless the student changes them" do
    create(:published_case, questions_count: 2)

    exam = build(mode: "full_exam").payload[:exam]

    expect(exam).to have_attributes(
      question_count: 2, feedback_timing: "at_end", seconds_per_question: 75, time_limit_seconds: 150
    )
  end

  it "takes the student's own conditions, where no clock at all is a choice" do
    create(:published_case, questions_count: 2)

    exam = described_class.call(
      user: user, mode: "full_exam", settings: { feedback_timing: "after_each", seconds_per_question: "" }
    ).payload[:exam]

    expect(exam).to have_attributes(feedback_timing: "after_each", seconds_per_question: nil, time_limit_seconds: nil)
  end

  it "falls back to the mode's timing for a value the form never offers" do
    create(:published_case)

    exam = described_class.call(user: user, mode: "custom", settings: { feedback_timing: "never" }).payload[:exam]

    expect(exam).to be_feedback_after_each
  end

  it "deals specialties in turn, so consecutive cases rarely share one" do
    3.times { create(:published_case, specialty: internal, questions_count: 1) }
    3.times { create(:published_case, specialty: pediatrics, questions_count: 1) }

    exam = build(filters: { question_count: 6 }).payload[:exam]

    specialties = cases_in(exam).map(&:specialty_id)
    expect(specialties.each_cons(2).none? { |a, b| a == b }).to be(true)
  end

  it "blocks by specialty, in reading order, when the student opts out of interleaving" do
    2.times { create(:published_case, specialty: pediatrics, questions_count: 1) }
    2.times { create(:published_case, specialty: internal, questions_count: 1) }

    exam = build(filters: { question_count: 10, interleave: "0" }).payload[:exam]

    expect(cases_in(exam).map(&:specialty)).to eq([internal, internal, pediatrics, pediatrics])
    expect(exam.filters).to include("interleave" => false)
  end

  it "narrows to the specialties, topic and difficulties chosen" do
    topic = create(:topic)
    wanted = create(:published_case, specialty: internal, topic: topic, difficulty: "high")
    create(:published_case, specialty: pediatrics, topic: topic, difficulty: "high")
    create(:published_case, specialty: internal, difficulty: "high")
    create(:published_case, specialty: internal, topic: topic, difficulty: "low")

    filters = { specialty_ids: ["", internal.id.to_s], topic_ids: ["", topic.id.to_s], difficulties: %w[high bogus] }
    exam = build(filters: filters)

    expect(cases_in(exam.payload[:exam])).to eq([wanted])
    expect(exam.payload[:exam].filters).to include(
      "specialty_ids" => [internal.id], "topic_ids" => [topic.id], "difficulties" => %w[high]
    )
  end

  describe "the student's own history" do
    let!(:seen) { create(:published_case, questions_count: 1) }
    let!(:unseen) { create(:published_case, questions_count: 1) }

    before do
      exam = create(:exam, user: user, question_count: 1)
      exam_question = exam.exam_questions.create!(question: seen.questions.first, clinical_case: seen, position: 1)
      exam_question.create_answer!(correct: false, answered_at: Time.current)
    end

    it "leaves out what the student has already seen" do
      expect(cases_in(build(filters: { unseen_only: "1" }).payload[:exam])).to eq([unseen])
    end

    it "brings back only what the student missed" do
      expect(cases_in(build(filters: { previously_wrong_only: "1" }).payload[:exam])).to eq([seen])
    end

    it "is the student's history, not anyone else's" do
      other = described_class.call(user: create(:user), mode: "custom", filters: { unseen_only: "1" })

      expect(cases_in(other.payload[:exam])).to contain_exactly(seen, unseen)
    end
  end

  it "ignores filters on a preset: those are fixed exams" do
    create(:published_case, specialty: pediatrics)

    exam = build(mode: "quick_quiz", filters: { specialty_ids: [internal.id] }).payload[:exam]

    expect(exam.question_count).to eq(2)
  end

  it "clamps the size of a custom exam to what the form offers" do
    create(:published_case)

    expect(build(filters: { question_count: 5000 }).payload[:exam].filters["question_count"]).to eq(100)
  end

  it "says so when nothing matches, rather than starting an empty exam" do
    result = build

    expect(result).to be_failure
    expect(result.errors.full_messages).to eq([I18n.t("exams.builder.nothing_matches")])
    expect(Exam.count).to eq(0)
  end

  it "refuses a mode it does not know" do
    expect(build(mode: "no_such_mode").errors.full_messages).to eq([I18n.t("exams.builder.unknown_mode")])
  end
end
