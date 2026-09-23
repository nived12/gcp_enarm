# What share of the published bank the student has actually seen, specialty by
# specialty, and which specialties they are leaving behind.
#
# Concentrating on Medicina Interna while neglecting Medicina Familiar and Salud Pública
# is a named way of failing the ENARM, so the transversal contexts are measured beside the
# troncales. A case counts as seen once any of its questions has been answered — in any
# exam, a discarded one included, because the student still read it. A case only drawn
# into an exam they never reached has not been seen.
module Stats
  class CoverageCalculator < ApplicationService
    # Below this many cases there is no pattern to name yet, only a first session.
    MINIMUM_SEEN_TO_JUDGE = 10

    # A specialty is being avoided when the student has seen less than half as much of it
    # as of the bank as a whole.
    NEGLECT_RATIO = 0.5

    Area = Data.define(:specialty, :seen, :published) do
      def share = (100.0 * seen / published if published.positive?)
    end

    Result = Data.define(:areas, :seen, :published, :neglected) do
      def share = (100.0 * seen / published if published.positive?)
    end

    def initialize(user)
      super()
      @user = user
    end

    def call
      published = ClinicalCase.status_published.group(:specialty_id).count
      seen = ClinicalCase.status_published.where(id: seen_cases).group(:specialty_id).count
      areas = Specialty.in_reading_order.map do |specialty|
        Area.new(specialty:, seen: seen.fetch(specialty.id, 0), published: published.fetch(specialty.id, 0))
      end

      result = Result.new(areas:, seen: seen.values.sum, published: published.values.sum, neglected: [])
      success(result.with(neglected: neglected(result)))
    end

    private

    attr_reader :user

    def seen_cases
      ExamQuestion.joins(:exam, :answer).where(exams: { user_id: user.id }).select(:clinical_case_id)
    end

    def neglected(result)
      return [] if result.seen < MINIMUM_SEEN_TO_JUDGE

      threshold = result.share * NEGLECT_RATIO
      result.areas.select { |area| area.published.positive? && area.share < threshold }.sort_by(&:share)
    end
  end
end
