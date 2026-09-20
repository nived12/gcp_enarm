# One of exactly four options on a question.
#
# A table rather than a jsonb array on purpose: *which* wrong answer a student picks is
# the most useful weak-spot signal in the product, and that only stays queryable if each
# distractor is a row.
class AnswerOption < ApplicationRecord
  belongs_to :question

  validates :text, presence: true
  validates :position, presence: true, uniqueness: { scope: :question_id }

  scope :correct, -> { where(correct: true) }
end
