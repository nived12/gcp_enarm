# What to read after a long exam: the topics the student did worse on than the exam as a
# whole, and for each, the guideline sections behind the questions they missed.
#
# The sections are named the way the live site's menu names them
# (GuidelineSection#menu_path), since the site has no address for a section and the path
# is what the reader clicks through. Misses the student put down to misreading the case
# or running out of time send them to no reading: the guideline is not what failed them.
# A miss with no reason given is unknown, and unknown still earns its reading.
#
# Only for an exam long enough that a topic's result means something: the exam-length
# modes always, anything else from twenty questions.
module Exams
  class RemediationReporter < ApplicationService
    MINIMUM_QUESTIONS = 20
    MINIMUM_TOPIC_QUESTIONS = 2
    MAX_TOPICS = 8

    Reading = Data.define(:section, :misses) do
      def guideline = section.guideline
    end

    Weakness = Data.define(:topic, :correct, :asked, :readings) do
      def percentage = 100.0 * correct / asked
    end

    Row = Data.define(:topic_id, :question_id, :correct, :reason) do
      # A miss that sends the student back to the guideline.
      def to_read? = !correct && Stats::WeakSpotCalculator::SLIP_REASONS.exclude?(reason)
    end

    def initialize(exam)
      super()
      @exam = exam
    end

    def call
      return success([]) unless eligible?

      success(weaknesses)
    end

    private

    attr_reader :exam

    def eligible?
      exam.status_completed? &&
        (Exam::EXAM_LENGTH_MODES.include?(exam.mode) || exam.question_count >= MINIMUM_QUESTIONS)
    end

    def weaknesses
      rows = exam.exam_questions.reorder(nil).joins(:clinical_case).left_joins(:answer)
                 .where.not(clinical_cases: { topic_id: nil })
                 .pluck("clinical_cases.topic_id", :question_id, "answers.correct", "answers.error_reason")
                 .map { |values| Row.new(*values) }
      return [] if rows.empty?

      overall = share_right(rows)
      weak = rows.group_by(&:topic_id).values
                 .select { |group| group.size >= MINIMUM_TOPIC_QUESTIONS && share_right(group) < overall }
                 .sort_by { |group| [share_right(group), -group.size, group.first.topic_id] }
                 .first(MAX_TOPICS)
      build(weak)
    end

    def share_right(rows)
      rows.count(&:correct).fdiv(rows.size)
    end

    def build(weak)
      topics = Topic.where(id: weak.map { |group| group.first.topic_id }).index_by(&:id)
      questions = Question.where(id: weak.flatten.select(&:to_read?).map(&:question_id))
                          .includes(recommendation: { guideline_section: :guideline }).index_by(&:id)

      weak.map do |group|
        missed = group.select(&:to_read?).filter_map { |row| questions.fetch(row.question_id).recommendation }
        Weakness.new(
          topic: topics.fetch(group.first.topic_id), correct: group.count(&:correct), asked: group.size,
          readings: readings(missed)
        )
      end
    end

    def readings(recommendations)
      recommendations.map(&:guideline_section).tally
                     .sort_by { |section, misses| [-misses, section.guideline_id, section.position] }
                     .map { |section, misses| Reading.new(section: section, misses: misses) }
    end
  end
end
