# One sitting: the cases drawn for it, the student's answers, and the clock.
#
# The clock is kept on the server and only runs while the exam is in progress. Time since
# `started_at` would count the night a paused exam sat in a closed tab, and "ran out of
# time" is one of the failure modes the simulator exists to rehearse.
class Exam < ApplicationRecord
  belongs_to :user

  has_many :exam_questions, -> { order(:position) }, dependent: :destroy, inverse_of: :exam
  has_many :answers, through: :exam_questions

  enum :mode,
    { quick_quiz: "quick_quiz", custom: "custom", full_exam: "full_exam", extended_exam: "extended_exam" },
    prefix: :mode

  enum :status,
    { in_progress: "in_progress", paused: "paused", completed: "completed", discarded: "discarded" },
    prefix: :status

  # Practice modes explain each answer as soon as it is given, one question at a time.
  # With explanations at the end the whole exam is one scrolling page, as the real one is:
  # every case on screen, answers changeable until the student finishes.
  enum :feedback_timing, { after_each: "after_each", at_end: "at_end" }, prefix: :feedback

  # How many questions each preset asks for. The real exam is ~280 items; 450 is the
  # length it had before 2021, and some students still train on it.
  QUESTION_COUNTS = { "quick_quiz" => 10, "full_exam" => 280, "extended_exam" => 450 }.freeze

  # The exam-length modes are rehearsals, so they default to the real exam's conditions:
  # explanations at the end and a clock. 75 seconds a question is the real sitting — six
  # hours for about 280 items — spread evenly; it is a budget for the whole exam, never a
  # limit on any one question.
  EXAM_LENGTH_MODES = %w[full_exam extended_exam].freeze
  SUGGESTED_SECONDS_PER_QUESTION = 75
  PACES = [60, 75, 90, 120].freeze

  validates :question_count, numericality: { greater_than: 0 }
  validates :seconds_per_question, inclusion: { in: PACES }, allow_nil: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :unfinished, -> { where(status: %w[in_progress paused]) }

  # A discarded exam is gone from the student's view — history, home, average — but its
  # rows stay: its answers still count against the free daily allowance, or answering
  # and discarding would get round it, and the cases in it were still seen.
  scope :kept, -> { where.not(status: "discarded") }

  def self.default_feedback_timing(mode)
    EXAM_LENGTH_MODES.include?(mode.to_s) ? "at_end" : "after_each"
  end

  def self.default_seconds_per_question(mode)
    SUGGESTED_SECONDS_PER_QUESTION if EXAM_LENGTH_MODES.include?(mode.to_s)
  end

  def current_elapsed
    return elapsed_seconds if running_since.nil?

    elapsed_seconds + (Time.current - running_since).to_i
  end

  def remaining_seconds
    [time_limit_seconds - current_elapsed, 0].max if time_limit_seconds
  end

  def time_up?
    remaining_seconds&.zero? || false
  end

  def unfinished?
    status_in_progress? || status_paused?
  end

  # Any exam the student no longer wants counted, finished or not. A finished exam is
  # their own record, and a sitting ended by accident at 0% should not weigh on their
  # average forever.
  def discard!
    return if status_discarded?

    update!(status: "discarded", elapsed_seconds: current_elapsed, running_since: nil)
  end

  def pause!
    return unless status_in_progress?

    update!(status: "paused", elapsed_seconds: current_elapsed, running_since: nil)
  end

  def resume!
    return unless status_paused?

    update!(status: "in_progress", running_since: Time.current)
  end

  # Unanswered questions count against the score: on the real exam a blank is a miss.
  def complete!
    return unless unfinished?

    correct = answers.where(correct: true).count
    update!(
      status: "completed", elapsed_seconds: current_elapsed, running_since: nil, completed_at: Time.current,
      score: (100.0 * correct / question_count).round(2)
    )
  end

  # The first question without an answer, which is where the student is. Nil once every
  # question has one.
  def current_question
    exam_questions.where.missing(:answer).first
  end

  # Correct answers against questions asked, per specialty, in the order CIFRHS breaks
  # ties by. Blanks count as asked and missed.
  def tally_by_specialty
    counts = exam_questions.reorder(nil).joins(:clinical_case).left_joins(:answer).group("clinical_cases.specialty_id")
                           .pluck("clinical_cases.specialty_id", Arel.sql("COUNT(*)"),
                             Arel.sql("COUNT(*) FILTER (WHERE answers.correct)")
                           )
    specialties = Specialty.where(id: counts.map(&:first)).index_by(&:id)

    counts.filter_map { |id, asked, correct| [specialties[id], correct, asked] if specialties[id] }
          .sort_by { |specialty, _correct, _asked| specialty.position }
  end
end
