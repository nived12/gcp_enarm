# How the student is doing and where they are weak: their average, and accuracy by
# specialty and by difficulty.
#
# The average is the one the home screen shows — the mean of finished exams' scores,
# each a plain percentage as CIFRHS reports it. The breakdowns count questions: every
# answered one, plus the blanks of a finished exam, which the real exam scores as misses.
# A question still ahead in an unfinished exam has not been asked yet.
#
# Discarded exams count for nothing here. Discarding is the student saying "that one did
# not count", and a stats page that kept it would say otherwise.
module Stats
  class PerformanceCalculator < ApplicationService
    # The order CIFRHS breaks ties in: correct answers in Alta first, then Media.
    DIFFICULTY_ORDER = %w[high medium low].freeze

    Tally = Data.define(:correct, :asked) do
      def self.none = new(correct: 0, asked: 0)
      def percentage = (100.0 * correct / asked if asked.positive?)
      def +(other) = Tally.new(correct: correct + other.correct, asked: asked + other.asked)
    end

    Result = Data.define(:average, :completed_exams, :overall, :by_specialty, :by_difficulty) do
      def empty? = overall.asked.zero?
    end

    def initialize(user)
      super()
      @user = user
    end

    def call
      average, completed = kept_exams.status_completed.pick(Arel.sql("AVG(score)"), Arel.sql("COUNT(*)"))
      rows = tallies

      success(
        Result.new(
          average: average, completed_exams: completed,
          overall: sum(rows), by_specialty: by_specialty(rows), by_difficulty: by_difficulty(rows)
        )
      )
    end

    private

    attr_reader :user

    def kept_exams
      user.exams.kept
    end

    # One query for every breakdown: [specialty_id, difficulty, Tally].
    def tallies
      counted_questions.group("clinical_cases.specialty_id", "clinical_cases.difficulty").pluck(
        "clinical_cases.specialty_id", "clinical_cases.difficulty",
        Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE answers.correct)")
      ).map { |specialty_id, difficulty, asked, correct| [specialty_id, difficulty, Tally.new(correct:, asked:)] }
    end

    def counted_questions
      ExamQuestion.joins(:exam, :clinical_case).left_joins(:answer)
                  .where(exams: { id: kept_exams.select(:id) })
                  .where("answers.id IS NOT NULL OR exams.status = 'completed'")
    end

    def sum(rows)
      rows.sum(Tally.none) { |_specialty_id, _difficulty, tally| tally }
    end

    # Reading order is the prelación order too: Medicina Interna, Pediatría,
    # Gineco-Obstetricia, Cirugía, then the transversal contexts.
    def by_specialty(rows)
      grouped = rows.group_by(&:first)
      Specialty.in_reading_order.where(id: grouped.keys).map { |specialty| [specialty, sum(grouped[specialty.id])] }
    end

    def by_difficulty(rows)
      grouped = rows.group_by(&:second)
      DIFFICULTY_ORDER.map { |difficulty| [difficulty, sum(grouped.fetch(difficulty, []))] }
    end
  end
end
