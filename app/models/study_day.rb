# What one student did on one day of their own calendar: the rollup the daily streak is
# computed from.
#
# The day turns over at midnight in the student's time zone. A 4 a.m. boundary was tried
# for the student studying after a guardia, and dropped by the owner on 2026-09-23:
# everyone reads 00:00 as a new day, so a count that carried on past it looked like a
# bug in the free allowance, not a kindness.
class StudyDay < ApplicationRecord
  belongs_to :user

  # Small on purpose: a two-minute session between consults keeps the streak. It rewards
  # showing up, not volume, so an intern on a 36-hour shift can still keep it without
  # giving up sleep for it.
  MINIMUM_QUESTIONS = 10

  validates :date, presence: true, uniqueness: { scope: :user_id }

  def self.date_for(time, time_zone)
    time.in_time_zone(time_zone).to_date
  end

  # The instants that belong to `date`, from its midnight to the next, as a range a
  # timestamp index can serve. Anything counted per study day — the streak, the free
  # allowance — must use this and `date_for`, so the two never disagree about "today".
  def self.time_range(date, time_zone)
    zone = ActiveSupport::TimeZone[time_zone]
    zone.local(date.year, date.month, date.day)...zone.local((date + 1).year, (date + 1).month, (date + 1).day)
  end

  # One pearls session: ten statements, about two minutes.
  PEARLS_PER_SESSION = 10

  # A whole pearls session counts as showing up as well as ten questions do. One card
  # does not: a single tap would otherwise keep the streak.
  def self.qualifies?(questions_answered, pearls_reviewed)
    questions_answered >= MINIMUM_QUESTIONS || pearls_reviewed >= PEARLS_PER_SESSION
  end

  # One statement, so two answers arriving together cannot lose a count between a read
  # and a write.
  def self.count_answer!(user, at: Time.current)
    count!(user, :questions_answered, at)
  end

  def self.count_pearl!(user, at: Time.current)
    count!(user, :pearls_reviewed, at)
  end

  INCREMENTS = {
    questions_answered: "questions_answered = study_days.questions_answered + 1, updated_at = excluded.updated_at",
    pearls_reviewed: "pearls_reviewed = study_days.pearls_reviewed + 1, updated_at = excluded.updated_at"
  }.freeze

  def self.count!(user, column, at)
    now = Time.current
    upsert(
      { user_id: user.id, date: date_for(at, user.time_zone), column => 1, created_at: now, updated_at: now },
      unique_by: %i[user_id date], on_duplicate: Arel.sql(INCREMENTS.fetch(column))
    )
  end
  private_class_method :count!
end
