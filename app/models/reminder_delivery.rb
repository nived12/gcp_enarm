# One reminder the dispatcher decided to send. The row is claimed before sending, and
# the unique index on (user, local date, slot) is what guarantees a student never gets
# two messages from the same slot on the same day, however many job runs overlap.
#
# The daily slot is shared by the study-day reminder and the streak nudge: at most one
# of the two a day. The exam countdown has its own slot, on three days of the year.
class ReminderDelivery < ApplicationRecord
  belongs_to :user

  enum :slot, { daily: "daily", countdown: "countdown" }, prefix: :slot, validate: true
  enum :kind, { study_day: "study_day", streak_at_risk: "streak_at_risk", exam_countdown: "exam_countdown" },
    prefix: :kind, validate: true

  validates :local_date, presence: true

  SLOTS = { "study_day" => "daily", "streak_at_risk" => "daily", "exam_countdown" => "countdown" }.freeze

  # True when this call took the slot, false when another run already had it.
  def self.claim(user:, local_date:, kind:, channels:)
    create!(user: user, local_date: local_date, kind: kind, slot: SLOTS.fetch(kind), channels: channels)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
