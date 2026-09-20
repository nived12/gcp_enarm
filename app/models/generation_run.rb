# One batch of LLM work, with what it actually cost.
#
# Every clinical case points at the run that produced it, so a prompt or a model that
# turns out to write bad distractors can be retired wholesale instead of case by case.
# That matters because generation is the one thing in this app that costs real money and
# cannot be reproduced: the same prompt against the same model returns different wording.
class GenerationRun < ApplicationRecord
  has_many :clinical_cases, dependent: :nullify

  enum :purpose,
    { generation: "generation", verification: "verification", bake_off: "bake_off" },
    prefix: :purpose

  enum :status,
    { running: "running", completed: "completed", failed: "failed" },
    prefix: :status

  validates :provider, presence: true
  validates :model, presence: true

  scope :recent, -> { order(started_at: :desc) }

  def total_tokens
    input_tokens + output_tokens
  end

  # What it took to land one usable case. The bake-off ranks models on this next to
  # quality: a cheaper model that needs two passes is not a cheaper model.
  def attempts_per_case
    return if cases_created.zero?

    (attempts.to_f / cases_created).round(2)
  end
end
