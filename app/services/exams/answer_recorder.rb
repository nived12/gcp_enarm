# Records the student's choice on one question of a running exam.
#
# One question at a time (explanations after each answer), only the question the student
# is on can be answered, and only once: the explanation has been shown. On the single
# page (explanations at the end) any question can be answered in any order and changed
# until the exam is finished, as on the real exam's answer sheet.
#
# Time spent is measured on the exam's own clock — the seconds it ran since the previous
# answer — so a pause is never billed to the question that was on screen when it began.
module Exams
  class AnswerRecorder < ApplicationService
    def initialize(exam_question, answer_option_id:)
      super()
      @exam_question = exam_question
      @answer_option_id = answer_option_id
    end

    def call
      return failure(I18n.t("exams.answers.not_running")) unless exam.status_in_progress?
      return time_up if exam.time_up?
      return failure(I18n.t("exams.answers.not_current")) unless answerable?
      return failure(I18n.t("exams.answers.choose_option")) if option.nil?
      return success(answer: change) if exam_question.answer

      access = exam.user.subscription_access_result
      return failure(access[:message]) unless access[:allowed]

      answer = exam_question.create_answer!(
        answer_option: option, correct: option.correct?, answered_at: Time.current,
        seconds_spent: [exam.current_elapsed - exam.answers.sum(:seconds_spent), 0].max
      )
      success(answer: answer)
    end

    def context_for_logging
      { exam_id: exam.id, exam_question_id: exam_question.id }
    end

    private

    attr_reader :exam_question, :answer_option_id

    def exam
      exam_question.exam
    end

    def answerable?
      exam.feedback_at_end? || exam.current_question == exam_question
    end

    # A changed mind costs no extra daily allowance and keeps the time first spent.
    def change
      exam_question.answer.tap { |answer| answer.update!(answer_option: option, correct: option.correct?) }
    end

    def option
      @option ||= exam_question.question.answer_options.find_by(id: answer_option_id)
    end

    # The clock ran out while the question was on screen. The exam ends there, as the
    # real one does, and the answer that arrived too late is not counted.
    def time_up
      exam.complete!
      failure(I18n.t("exams.answers.time_up"))
    end
  end
end
