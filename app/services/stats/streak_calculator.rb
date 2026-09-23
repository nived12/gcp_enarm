# The daily streak, derived from the student's study days every time it is asked for.
#
# Built to be keepable by someone on guardias every third or fourth night:
#
# * a day counts with a small minimum (StudyDay::MINIMUM_QUESTIONS);
# * every seventh day studied within a streak earns a freeze, at most two banked, and a
#   missed day spends one automatically. A day a freeze covered keeps the streak going
#   but does not add to it or to the next freeze;
# * today is never a missed day — there is time left until midnight;
# * a lost streak simply ends. The next day studied starts a new one and the best is kept.
module Stats
  class StreakCalculator < ApplicationService
    DAYS_PER_FREEZE = 7
    MAX_FREEZES = 2

    Result = Data.define(:current, :best, :freezes, :frozen_dates, :today_questions, :today_done) do
      def minimum = StudyDay::MINIMUM_QUESTIONS
      def today_remaining = [minimum - today_questions, 0].max
    end

    def initialize(user, today: user.study_date)
      super()
      @user = user
      @today = today
      @current = 0
      @best = 0
      @toward_freeze = 0
      @freezes = 0
      @frozen_dates = []
    end

    def call
      rows = user.study_days.where(date: ..today).order(:date).pluck(:date, :questions_answered, :pearls_reviewed)
      studied = rows.filter_map { |date, questions, pearls| date if StudyDay.qualifies?(questions, pearls) }

      studied.each_with_index do |day, index|
        bridge(studied[index - 1], day) if index.positive?
        study
      end
      bridge(studied.last, today) if studied.any?

      today_row = rows.find { |date, _questions, _pearls| date == today }
      success(
        Result.new(
          current: @current, best: @best, freezes: @freezes, frozen_dates: @frozen_dates,
          today_questions: today_row&.second || 0, today_done: studied.last == today
        )
      )
    end

    private

    attr_reader :user, :today

    def study
      @current += 1
      @best = [@best, @current].max
      @toward_freeze += 1
      return unless @toward_freeze == DAYS_PER_FREEZE

      @toward_freeze = 0
      @freezes = [@freezes + 1, MAX_FREEZES].min
    end

    # The days strictly between two studied days — or between the last one and today —
    # are missed. Freezes cover them one each; when they run out the streak is over.
    def bridge(from, to)
      missed = (from + 1...to).to_a
      if missed.size <= @freezes
        @freezes -= missed.size
        @frozen_dates.concat(missed)
      else
        @current = 0
        @toward_freeze = 0
        @freezes = 0
        @frozen_dates = []
      end
    end
  end
end
