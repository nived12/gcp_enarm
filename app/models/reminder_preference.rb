# What a student asked to be reminded of, on which channel, and at what time of their day.
#
# Everything is off until the student turns it on. Push has no switch here: a device
# that subscribed is the switch, so the preference can never say "push" for a student
# with nowhere to push to.
class ReminderPreference < ApplicationRecord
  belongs_to :user

  # On the hour, 06:00 to 22:00: few enough to show as pills, and a reminder does not
  # need to be precise to the minute to be useful. Stored in minutes so that finer
  # choices, should anyone ask, need no migration.
  MINUTE_CHOICES = (6..22).map { |hour| hour * 60 }.freeze

  # The streak nudge goes out in the evening, late enough that the day's study could
  # already have happened and early enough to still do ten questions before midnight.
  STREAK_MINUTE = 20 * 60

  # A reminder is sent only in the hour after its time. The job gets four chances at it,
  # so a missed tick or a deploy costs nothing, and changing the time at 18:00 to 08:00
  # does not fire this morning's reminder in the middle of the evening.
  WINDOW_MINUTES = 60

  validates :minute_of_day, inclusion: { in: MINUTE_CHOICES }

  scope :wanting_any, -> { where(study_days: true).or(where(streak_at_risk: true)).or(where(exam_countdown: true)) }

  def any_reminder?
    study_days || streak_at_risk || exam_countdown
  end

  def self.due_at?(minute, local_time)
    elapsed = (local_time.hour * 60) + local_time.min - minute
    elapsed >= 0 && elapsed < WINDOW_MINUTES
  end
end
