# How the student is doing and where they are weak: their average, and accuracy by
# specialty, by difficulty, and by how sure they said they were — the last tells them
# whether to trust their first instinct on exam day.
#
# The average is the one the home screen shows — the mean of finished exams' scores,
# each a plain percentage as CIFRHS reports it. The breakdowns count questions: every
# answered one, plus the blanks of a finished exam, which the real exam scores as misses.
# A question still ahead in an unfinished exam has not been asked yet.
#
# Discarded exams count for nothing here. Discarding is the student saying "that one did
# not count", and a stats page that kept it would say otherwise.
#
# By specialty means by area, as everywhere else (`ClinicalCase.in_area`): a question
# counts under what its case is about and under the setting it happens in, so a
# pneumonia seen in urgencias is in Medicina Interna's row and in Urgencias'. The rows
# then add up to more than the questions asked — the page says so — while the overall
# figure and the difficulty rows still count each question once.
module Stats
  class PerformanceCalculator < ApplicationService
    # The order CIFRHS breaks ties in: correct answers in Alta first, then Media.
    DIFFICULTY_ORDER = %w[high medium low].freeze

    Tally = Data.define(:correct, :asked) do
      def self.none = new(correct: 0, asked: 0)
      def percentage = (100.0 * correct / asked if asked.positive?)
      def +(other) = Tally.new(correct: correct + other.correct, asked: asked + other.asked)
    end

    Result = Data.define(:average, :completed_exams, :overall, :by_specialty, :by_difficulty, :by_confidence) do
      def empty? = overall.asked.zero?

      # True when some question sits in two rows, which the page has to explain.
      def specialties_overlap? = by_specialty.sum { |_specialty, tally| tally.asked } > overall.asked
    end

    def initialize(user)
      super()
      @user = user
    end

    def call
      average, completed = kept_exams.status_completed.pick(Arel.sql("AVG(score)"), Arel.sql("COUNT(*)"))
      rows = tallies_by_difficulty

      success(
        Result.new(
          average: average, completed_exams: completed,
          overall: rows.values.sum(Tally.none), by_specialty: by_specialty, by_difficulty: by_difficulty(rows),
          by_confidence: by_confidence
        )
      )
    end

    private

    attr_reader :user

    def kept_exams
      user.exams.kept
    end

    # Difficulty => Tally. Each question once, which is what the overall figure sums.
    def tallies_by_difficulty
      tally(counted_questions, "clinical_cases.difficulty").to_h
    end

    def tally(questions, key)
      questions.group(key).pluck(
        key, Arel.sql("COUNT(*)"), Arel.sql("COUNT(*) FILTER (WHERE answers.correct)")
      ).map { |group, asked, correct| [group, Tally.new(correct:, asked:)] }
    end

    def counted_questions
      ExamQuestion.joins(:exam, :clinical_case).left_joins(:answer)
                  .where(exams: { id: kept_exams.select(:id) })
                  .where("answers.id IS NOT NULL OR exams.status = 'completed'")
    end

    # Reading order is the prelación order too: Medicina Interna, Pediatría,
    # Gineco-Obstetricia, Cirugía, then the transversal contexts.
    def by_specialty
      tallies = tally(counted_questions.joins(ClinicalCase::AREAS_JOIN), "areas.area_id").to_h
      Specialty.in_reading_order.where(id: tallies.keys).map { |specialty| [specialty, tallies[specialty.id]] }
    end

    # Only the levels the student has used, in Answer::CONFIDENCES order; empty until they
    # mark one, so the page can leave the section out.
    def by_confidence
      tallies = tally(counted_questions.where.not(answers: { confidence: nil }), "answers.confidence").to_h
      Answer::CONFIDENCES.filter_map { |level| [level, tallies[level]] if tallies[level] }
    end

    def by_difficulty(tallies)
      DIFFICULTY_ORDER.map { |difficulty| [difficulty, tallies.fetch(difficulty, Tally.none)] }
    end
  end
end
