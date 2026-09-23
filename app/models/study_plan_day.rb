# One day of a study plan and what it asks for.
#
# A `topics` day is the syllabus: two or three named topics to read and a quiz on exactly
# those. A `case_workshop` closes a specialty with cases from the whole of it, `review`
# closes a pass with a mixed quiz, `assessment` is a full-length simulacro, and a
# `catch_up` day is slack left on purpose so falling behind has somewhere to go.
class StudyPlanDay < ApplicationRecord
  belongs_to :study_plan
  belongs_to :specialty, optional: true
  belongs_to :exam, optional: true
  has_many :day_topics, -> { order(:position) }, class_name: "StudyPlanDayTopic", dependent: :delete_all,
    inverse_of: :study_plan_day
  has_many :topics, through: :day_topics

  enum :kind,
    {
      topics: "topics", case_workshop: "case_workshop", review: "review",
      assessment: "assessment", catch_up: "catch_up"
    },
    prefix: :kind

  # Enough to cover two or three topics without turning a reading day into an exam.
  TOPIC_QUIZ_QUESTIONS = 10
  WORKSHOP_QUESTIONS = 20
  REVIEW_QUESTIONS = 20

  validates :date, presence: true
  validates :pass_number, inclusion: { in: 1..3 }

  # Done when the quiz it launched was finished, or when the student said so on a day
  # that has no quiz to finish.
  def done?
    completed_at.present? || exam&.status_completed? || false
  end

  # The topics of the day that have published cases. A topic without cases is still read
  # on its day; it just has nothing to be quizzed on yet.
  def quiz_topics
    topics.where(id: ClinicalCase.status_published.select(:topic_id))
  end

  # A day of Medicina Familiar, Urgencias or Salud Pública also quizzes the cases set in
  # that context. The bank files cases by subject, so a context's own topics hold almost
  # none, and without these its days would stay reading days however many consults and
  # emergencies the bank holds.
  def setting_cases
    return ClinicalCase.none unless kind_topics? && specialty&.kind_cross_cutting?

    ClinicalCase.status_published.where(setting: specialty)
  end

  def quiz?
    return false if kind_catch_up?
    return quiz_topics.exists? || setting_cases.exists? if kind_topics?

    true
  end

  # What Exams::Builder is asked for. The review and the simulacro draw from the whole
  # bank, interleaved, as the exam does.
  def exam_request
    case kind
    when "topics"
      filters = { topic_ids: quiz_topics.ids, question_count: TOPIC_QUIZ_QUESTIONS }
      filters[:also_setting_ids] = [specialty_id] if setting_cases.exists?
      { mode: "custom", filters: filters }
    when "case_workshop"
      { mode: "custom", filters: { specialty_ids: [specialty_id], question_count: WORKSHOP_QUESTIONS } }
    when "review"
      { mode: "custom", filters: { question_count: REVIEW_QUESTIONS } }
    else
      { mode: "full_exam", filters: {} }
    end
  end
end
