# What the student chose on one exam question, and — when it was wrong — why, in their
# own words.
class Answer < ApplicationRecord
  belongs_to :exam_question
  belongs_to :answer_option, optional: true

  has_one :exam, through: :exam_question

  # The single most-cited study mistake is reviewing the score rather than the cause.
  # This is the cause, told by the only person who knows it. Never infer it from timing
  # or anything else: an empty value means they did not say, and weak-spot targeting has
  # to treat that as unknown rather than as not knowing.
  enum :error_reason,
    {
      did_not_know: "did_not_know", confused_diagnoses: "confused_diagnoses",
      misread_case: "misread_case", ran_out_of_time: "ran_out_of_time"
    },
    prefix: :error, validate: { allow_nil: true }

  validates :answered_at, presence: true
  validates :exam_question_id, uniqueness: true
  validate :option_belongs_to_the_question

  # A new answer, a changed one and a reason given later all move the case's review
  # schedule, which is replayed from the answers rather than kept alongside them.
  after_commit :reschedule_review, on: %i[create update]

  private

  def reschedule_review
    Reviews::CaseScheduler.call(exam_question.exam.user, [exam_question.clinical_case_id])
  end

  def option_belongs_to_the_question
    return if answer_option.nil? || answer_option.question_id == exam_question&.question_id

    errors.add(:answer_option, :invalid)
  end
end
