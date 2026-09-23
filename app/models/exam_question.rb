# A question's place in one exam. The case is stored alongside it so an exam can be
# walked case by case without going through the question for every row.
class ExamQuestion < ApplicationRecord
  belongs_to :exam
  belongs_to :question
  belongs_to :clinical_case

  has_one :answer, dependent: :destroy

  validates :position, presence: true, uniqueness: { scope: :exam_id }

  def next_in_exam
    exam.exam_questions.find_by(position: position + 1)
  end
end
