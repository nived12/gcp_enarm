# Records the student's own grade for one pearl and counts it towards today's streak.
#
# The four buttons map to SM-2 qualities the way the algorithm's own scale reads: "again"
# is 1 (not recalled — a lapse), "hard" 3 (recalled with serious difficulty), "good" 4,
# "easy" 5. A pearl is graded once a day: the same card sent twice — a double tap, a
# reload — is neither rescheduled again nor counted again.
module Pearls
  class ReviewRecorder < ApplicationService
    QUALITIES = { "again" => 1, "hard" => 3, "good" => 4, "easy" => 5 }.freeze

    def initialize(user, recommendation, grade:)
      super()
      @user = user
      @recommendation = recommendation
      @grade = grade.to_s
    end

    def call
      return failure(I18n.t("pearls.unknown_grade")) unless QUALITIES.key?(grade)

      today = user.study_date
      card = ReviewCard.find_or_initialize_by(user: user, recommendation: recommendation)
      return success(card: card) if card.last_reviewed_on == today

      ReviewCard.transaction do
        card.schedule(QUALITIES.fetch(grade), on: today).save!
        StudyDay.count_pearl!(user)
      end
      success(card: card)
    end

    private

    attr_reader :user, :recommendation, :grade
  end
end
