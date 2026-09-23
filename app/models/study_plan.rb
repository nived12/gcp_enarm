# A student's calendar to exam day, in Dr. Re's shape: the syllabus walked three times,
# each day naming its topics. One per student; starting over replaces it.
#
# The template is the shape of the student's week — which days are for resting — rather
# than a length in months: the length already follows from today and the exam date.
class StudyPlan < ApplicationRecord
  belongs_to :user
  has_many :days, -> { order(:date) }, class_name: "StudyPlanDay", dependent: :destroy, inverse_of: :study_plan

  enum :template, { six_days: "six_days", five_days: "five_days", every_day: "every_day" },
    prefix: :template, validate: true

  # Date#wday numbers, Sunday first.
  REST_WEEKDAYS = { "six_days" => [0], "five_days" => [6, 0], "every_day" => [] }.freeze

  # Shorter than three weeks there is nothing to plan, only to cram; longer than two years
  # and the exam is one the student has not registered for yet.
  MINIMUM_DAYS = 21
  MAXIMUM_DAYS = 730

  # ENARM 2026 opened on 28 September. CIFRHS announces each year's dates in the
  # convocatoria, months ahead, so this is only the starting value of a field the
  # student can change.
  USUAL_EXAM_MONTH = 9
  USUAL_EXAM_DAY = 28

  validates :starts_on, presence: true
  validate :exam_date_within_reach

  # The next usual exam date with at least MINIMUM_DAYS to prepare. Someone planning a
  # week before the exam is planning for the one after it.
  def self.default_exam_date(today)
    date = Date.new(today.year, USUAL_EXAM_MONTH, USUAL_EXAM_DAY)
    date = date.next_year while date < today + MINIMUM_DAYS
    date
  end

  def rest_day?(date)
    REST_WEEKDAYS.fetch(template).include?(date.wday)
  end

  # Every day from `from` up to the eve of the exam that is not a rest day.
  def study_dates(from)
    (from...exam_date).reject { |date| rest_day?(date) }
  end

  def day_on(date)
    days.includes(:specialty, :exam, :topics).find_by(date: date)
  end

  def pass_count
    days.maximum(:pass_number)
  end

  # Days whose date has gone by without being done. A catch-up day that passed is not a
  # debt: it was the slack, and the slack was spent.
  def missed_days(today)
    days.where(date: ...today).where.not(kind: "catch_up").includes(:exam).reject(&:done?)
  end

  private

  # On :base with a whole sentence, so the form can show it as written.
  def exam_date_within_reach
    return if starts_on.blank?

    problem = if exam_date.blank? then :exam_date_missing
    elsif exam_date < starts_on + MINIMUM_DAYS then :exam_date_too_close
    elsif exam_date > starts_on + MAXIMUM_DAYS then :exam_date_too_far
    end
    errors.add(:base, problem, message: I18n.t("study_plans.errors.#{problem}", minimum: MINIMUM_DAYS)) if problem
  end
end
