# What share of the published bank the student has actually seen, specialty by
# specialty, and which specialties they are leaving behind.
#
# Concentrating on Medicina Interna while neglecting Medicina Familiar and Salud Pública
# is a named way of failing the ENARM, so the transversal contexts are measured beside the
# troncales. "Seen" is `ExamQuestion.answered_by`: answered, discarded exams included.
#
# An area holds the cases about it and the cases set in it (`ClinicalCase.in_area`): the
# bank files cases by subject, so Medicina Familiar has almost none of its own, yet most
# cases happen in a family-medicine consult. Areas overlap, so the whole-bank figures
# count cases, never the areas' sum.
module Stats
  class CoverageCalculator < ApplicationService
    # Below this many cases there is no pattern to name yet, only a first session.
    MINIMUM_SEEN_TO_JUDGE = 10

    # A specialty is being avoided when the student has seen less than half as much of it
    # as of the bank as a whole.
    NEGLECT_RATIO = 0.5

    Area = Data.define(:specialty, :seen, :published) do
      def share = (100.0 * seen / published if published.positive?)
      def empty? = published.zero?
    end

    Result = Data.define(:areas, :seen, :published, :neglected) do
      def share = (100.0 * seen / published if published.positive?)
    end

    def initialize(user)
      super()
      @user = user
    end

    def call
      published_cases = ClinicalCase.status_published
      seen_cases = published_cases.where(id: answered_cases)
      published = published_cases.count_by_area
      seen = seen_cases.count_by_area
      areas = Specialty.in_reading_order.map do |specialty|
        Area.new(specialty:, seen: seen.fetch(specialty.id, 0), published: published.fetch(specialty.id, 0))
      end

      result = Result.new(areas:, seen: seen_cases.count, published: published_cases.count, neglected: [])
      success(result.with(neglected: neglected(result)))
    end

    private

    attr_reader :user

    def answered_cases
      ExamQuestion.answered_by(user).select(:clinical_case_id)
    end

    # An area with nothing published cannot be neglected: there is nothing in it to see.
    def neglected(result)
      return [] if result.seen < MINIMUM_SEEN_TO_JUDGE

      threshold = result.share * NEGLECT_RATIO
      result.areas.reject(&:empty?).select { |area| area.share < threshold }.sort_by(&:share)
    end
  end
end
