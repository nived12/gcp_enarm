# A student's "Sugerir cambios" on a question they have answered.
#
# Generated questions auto-publish behind machine verification, so these reports are the
# human check that runs after publication. A report never changes the case by itself — a
# student cannot pull an item out of everyone else's bank — it puts the case in front of
# a reviewer, who flags, retires or leaves it.
class QuestionReport < ApplicationRecord
  belongs_to :user
  belongs_to :question
  belongs_to :resolved_by, class_name: "User", optional: true

  has_one :clinical_case, through: :question

  enum :reason,
    { incorrect_answer: "incorrect_answer", ambiguous: "ambiguous", outdated_guideline: "outdated_guideline",
      wrong_explanation: "wrong_explanation", typo: "typo", other: "other" },
    prefix: :reason, validate: true

  enum :status, { open: "open", resolved: "resolved", dismissed: "dismissed" }, prefix: :status

  COMMENT_LIMIT = 2_000
  CLOSED = %w[resolved dismissed].freeze

  validates :comment, length: { maximum: COMMENT_LIMIT }
  # "Otro" says nothing a reviewer can act on until the student says what it is.
  validates :comment, presence: true, if: :reason_other?
  validates :question_id, uniqueness: { scope: :user_id, conditions: -> { status_open } }, if: :status_open?
  validates :resolved_by, presence: true, unless: :status_open?

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Open reports per case, for marking the cases in a list without a query per row.
  def self.open_counts_by_case(case_ids)
    status_open.joins(:question).where(questions: { clinical_case_id: case_ids })
               .group("questions.clinical_case_id").count
  end

  # Closing records who closed it and when, so a student's report is never silently lost.
  def close(status:, note:, by:)
    return false unless CLOSED.include?(status)

    update(status: status, resolution_note: note.presence, resolved_by: by, resolved_at: Time.current)
  end
end
