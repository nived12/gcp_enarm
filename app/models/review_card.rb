# One student's spaced-repetition schedule for one clinical case they missed, or for one
# guideline statement studied as a pearl.
#
# The scheduler is SM-2 as SuperMemo published it (Wozniak, 1990), unchanged, because it
# is deterministic, well understood and cheap: a quality from 0 to 5 per review, an ease
# factor that never drops below 1.3, and intervals of 1 day, 6 days, then the previous
# interval times the ease. A quality below 3 is a lapse: the card starts again from one
# day. Where the quality comes from differs — cases grade themselves from the answers,
# pearls are graded by the student — and is documented where it is decided.
class ReviewCard < ApplicationRecord
  belongs_to :user
  belongs_to :clinical_case, optional: true
  belongs_to :recommendation, optional: true

  QUALITIES = (0..5)
  PASSING_QUALITY = 3
  MINIMUM_EASE = 1.3
  INITIAL_EASE = 2.5

  # Exactly one of the two subjects is set; the database's check constraint holds that.
  validates :due_on, presence: true

  scope :cases, -> { where.not(clinical_case_id: nil) }
  scope :pearls, -> { where.not(recommendation_id: nil) }
  scope :due, ->(date) { where(due_on: ..date) }

  # Cases a student can actually be shown again: a case withdrawn after they missed it
  # stays scheduled but out of sight, since only published cases reach students.
  scope :published_cases, -> { cases.where(clinical_case_id: ClinicalCase.status_published.select(:id)) }

  # One review on `date`. The interval grows with the ease the card had before this
  # review; the ease then moves by the SM-2 formula, on a lapse as well as on a pass.
  def schedule(quality, on:)
    raise ArgumentError, "quality must be in #{QUALITIES}" unless QUALITIES.cover?(quality)

    if quality >= PASSING_QUALITY
      self.interval_days = next_interval
      self.repetitions += 1
    else
      self.interval_days = 1
      self.repetitions = 0
      self.lapses += 1
    end
    self.ease_factor = [ease_factor + 0.1 - ((5 - quality) * (0.08 + ((5 - quality) * 0.02))), MINIMUM_EASE].max
    self.reviews_count += 1
    self.last_reviewed_on = on
    self.due_on = on + interval_days
    self
  end

  # Back to a card never reviewed, so a case's whole history can be replayed onto it.
  def reset
    assign_attributes(
      ease_factor: INITIAL_EASE, interval_days: 0, repetitions: 0, lapses: 0, reviews_count: 0,
      last_reviewed_on: nil
    )
    self
  end

  private

  def next_interval
    case repetitions
    when 0 then 1
    when 1 then 6
    else (interval_days * ease_factor).round
    end
  end
end
