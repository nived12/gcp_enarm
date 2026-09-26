# A question's place in one exam. The case is stored alongside it so an exam can be
# walked case by case without going through the question for every row.
class ExamQuestion < ApplicationRecord
  belongs_to :exam
  belongs_to :question
  belongs_to :clinical_case

  has_one :answer, dependent: :destroy

  validates :position, presence: true, uniqueness: { scope: :exam_id }

  # What the student has seen: a case counts once any of its questions has been answered,
  # in any exam, a discarded one included, because they still read it. A case only drawn
  # into an exam they never reached has not been seen. Every "seen" and "unseen" in the
  # product — the builder's filter, coverage, pearls, weak spots — reads this.
  scope :answered_by, ->(user) { joins(:exam, :answer).where(exams: { user_id: user.id }) }

  # Whether its answer, explanation and citation are on screen: after each answer one at a
  # time, and only once the exam is over on the single page.
  def revealed?
    exam.status_completed? || (exam.feedback_after_each? && answer.present?)
  end

  # The options in the order this exam shows them. The model writes the correct answer
  # first, so the stored order would make it always A. Seeded by this row's id, the order
  # is new in every exam and stays put across reloads and in the review, so the letter a
  # student picked is the letter they read back.
  def answer_options
    question.answer_options.to_a.shuffle(random: Random.new(id))
  end

  def next_in_exam
    exam.exam_questions.find_by(position: position + 1)
  end
end
