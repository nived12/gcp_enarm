require "rails_helper"

RSpec.describe Stats::PerformanceCalculator do
  let(:user) { create(:user) }
  let(:internal) { create(:specialty, name: "Medicina Interna", position: 1) }
  let(:pediatrics) { create(:specialty, name: "Pediatría", position: 2) }
  let(:hard_internal) { create(:published_case, specialty: internal, difficulty: "high") }
  let(:easy_pediatrics) { create(:published_case, specialty: pediatrics, difficulty: "low") }
  let(:unfiled) { create(:published_case, questions_count: 1, difficulty: "medium") }

  # choices maps each question to true (right), false (wrong) or nil (left blank).
  def sit(cases, choices, status: "completed")
    questions = cases.flat_map(&:questions)
    exam = create(:exam, user: user, question_count: questions.size)
    questions.each.with_index(1) do |question, position|
      exam_question = exam.exam_questions.create!(
        question: question, clinical_case: question.clinical_case,
        position: position
      )
      next if (right = choices.fetch(position - 1)).nil?

      option = question.answer_options.find { |candidate| candidate.correct? == right }
      exam_question.create_answer!(answer_option: option, correct: right, answered_at: Time.current)
    end
    status == "completed" ? exam.complete! : exam.update!(status: status)
    exam
  end

  def performance
    described_class.call(user).payload
  end

  it "has nothing to say before the first answer" do
    expect(performance).to be_empty
    expect(performance).to have_attributes(average: nil, completed_exams: 0, by_specialty: [])
    expect(performance.by_difficulty).to eq(
      %w[high medium low].map { |difficulty|
        [difficulty, described_class::Tally.none]
      }
    )
    expect(performance.overall.percentage).to be_nil
  end

  it "counts answers and a finished exam's blanks, never a discarded exam or a question not reached yet" do
    sit([hard_internal, easy_pediatrics, unfiled], [true, false, true, nil, true])
    sit([hard_internal], [true, nil], status: "in_progress")
    sit([easy_pediatrics, unfiled], [true, true, true], status: "discarded")

    expect(performance).to have_attributes(average: 60, completed_exams: 1)
    expect(performance.overall).to eq(described_class::Tally.new(correct: 4, asked: 6))
    expect(performance.overall.percentage).to be_within(0.01).of(66.67)
  end

  it "breaks accuracy down by specialty in reading order and by difficulty in the tie-break order" do
    sit([easy_pediatrics, hard_internal, unfiled], [true, nil, true, false, true])

    expect(performance.by_specialty).to eq(
      [
            [internal, described_class::Tally.new(correct: 1, asked: 2)],
            [pediatrics, described_class::Tally.new(correct: 1, asked: 2)]
          ]
    )
    expect(performance.by_difficulty).to eq(
      [
            ["high", described_class::Tally.new(correct: 1, asked: 2)],
            ["medium", described_class::Tally.new(correct: 1, asked: 1)],
            ["low", described_class::Tally.new(correct: 1, asked: 2)]
          ]
    )
  end

  it "reads everything in a fixed handful of queries, however many exams there are" do
    3.times { sit([hard_internal, easy_pediatrics], [true, false, true, false]) }

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { performance }

    expect(queries).to be <= 4
  end

  describe "a question counted by subject and by setting" do
    let(:emergency) { create(:emergency_setting, position: 6) }

    it "puts the question in both rows and says the rows overlap, while the overall figure counts it once" do
      hard_internal.update!(setting: emergency)
      sit([hard_internal, easy_pediatrics], [true, false, true, false])

      expect(performance.by_specialty).to eq(
        [
          [internal, described_class::Tally.new(correct: 1, asked: 2)],
          [pediatrics, described_class::Tally.new(correct: 1, asked: 2)],
          [emergency, described_class::Tally.new(correct: 1, asked: 2)]
        ]
      )
      expect(performance.overall).to eq(described_class::Tally.new(correct: 2, asked: 4))
      expect(performance).to be_specialties_overlap
    end

    it "counts a case about Urgencias set in urgencias once, and then nothing overlaps" do
      kase = create(:published_case, specialty: emergency, setting: emergency, questions_count: 1)
      sit([kase], [true])

      expect(performance.by_specialty).to eq([[emergency, described_class::Tally.new(correct: 1, asked: 1)]])
      expect(performance).not_to be_specialties_overlap
    end
  end
end
