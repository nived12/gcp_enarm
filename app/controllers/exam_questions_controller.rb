# One question of a sitting, before and after it is answered.
#
# Nothing that helps answer a question is on screen until it has been answered: the
# explanation, the cited statement and the guideline figure it points at all belong to
# the answer. A guideline's own algorithms and tables shown beside the vignette would
# turn the item into an open-book lookup.
class ExamQuestionsController < ApplicationController
  def show
    @exam = Current.user.exams.find(params[:exam_id])
    @exam_question = @exam.exam_questions
                          .includes(:answer, clinical_case: [:guideline, :clinical_image],
                            question: [:answer_options, { recommendation: { guideline_section: :guideline } }]
                          )
                          .find_by!(position: params[:position])
    return if viewable?

    redirect_to where_the_student_is
  end

  private

  # A running exam shows the question the student is on and, one question at a time, the
  # ones already answered. Anything else — a question ahead, a paused or timed-out exam,
  # an exam on a single page — goes back through the exam, which knows where the student
  # belongs.
  def viewable?
    return true if @exam.status_completed?
    return false unless @exam.status_in_progress? && !@exam.time_up?
    return true if @exam_question == @exam.current_question

    @exam_question.answer.present? && @exam.feedback_after_each?
  end

  # A question not viewable one at a time is one ahead of the student, so there is always
  # a current question to send them to.
  def where_the_student_is
    return exam_path(@exam) if !@exam.status_in_progress? || @exam.time_up?
    return exam_path(@exam, anchor: helpers.dom_id(@exam_question)) if @exam.feedback_at_end?

    exam_question_path(@exam, @exam.current_question.position)
  end
end
