# What one student did on one day of their own calendar: the rollup the daily streak is
# computed from.
#
# The day turns over at 4 a.m. in the student's time zone, not at midnight. Someone
# answering questions at 1 a.m. after a guardia is still on the day they started, and a
# boundary at midnight would ask them to stay up to keep yesterday alive.
class StudyDay < ApplicationRecord
  belongs_to :user

  DAY_STARTS_AT_HOUR = 4

  # Small on purpose: a two-minute session between consults keeps the streak. It rewards
  # showing up, not volume, so an intern on a 36-hour shift can still keep it without
  # giving up sleep for it.
  MINIMUM_QUESTIONS = 10

  validates :date, presence: true, uniqueness: { scope: :user_id }

  # Read off the wall clock rather than by subtracting four hours, so the boundary stays
  # at 4 a.m. on the night a border zone changes its clocks.
  def self.date_for(time, time_zone)
    local = time.in_time_zone(time_zone)
    local.hour < DAY_STARTS_AT_HOUR ? local.to_date - 1 : local.to_date
  end

  # The instants that belong to `date`, from its 4 a.m. to the next one, as a range a
  # timestamp index can serve. Anything counted per study day — the streak, the free
  # allowance — must use this and `date_for`, so the two never disagree about "today".
  def self.time_range(date, time_zone)
    zone = ActiveSupport::TimeZone[time_zone]
    starts = ->(day) { zone.local(day.year, day.month, day.day, DAY_STARTS_AT_HOUR) }
    starts.call(date)...starts.call(date + 1)
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
