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

  def self.date_for(time, time_zone)
    (time.in_time_zone(time_zone) - DAY_STARTS_AT_HOUR.hours).to_date
  end

  # A pearls session (Phase 5b) counts as showing up as well as ten questions do.
  def self.qualifies?(questions_answered, pearls_reviewed)
    questions_answered >= MINIMUM_QUESTIONS || pearls_reviewed.positive?
  end

  # One statement, so two answers arriving together cannot lose a count between a read
  # and a write.
  def self.count_answer!(user, at: Time.current)
    now = Time.current
    upsert(
      { user_id: user.id, date: date_for(at, user.time_zone), questions_answered: 1, created_at: now, updated_at: now },
      unique_by: %i[user_id date],
      on_duplicate: Arel.sql(
        "questions_answered = study_days.questions_answered + 1, updated_at = excluded.updated_at"
      )
    )
  end
end
