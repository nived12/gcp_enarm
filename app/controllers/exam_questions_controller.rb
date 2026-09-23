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

  # One question at a time, a running exam opens any of its questions: back to an answer
  # to reread it, or ahead past one left for later. A paused or timed-out exam goes back
  # through the exam, which knows what to show; the single page shows the question in
  # place.
  def viewable?
    return true if @exam.status_completed?

    @exam.status_in_progress? && !@exam.time_up? && @exam.feedback_after_each?
  end

  def where_the_student_is
    return exam_path(@exam, anchor: helpers.dom_id(@exam_question)) if @exam.status_in_progress? && !@exam.time_up?

    exam_path(@exam)
  end
end
