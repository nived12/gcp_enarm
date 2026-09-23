class AnswersController < ApplicationController
  include UpgradePath

  before_action :set_exam_question

  def create
    result = Exams::AnswerRecorder.call(@exam_question, answer_option_id: params[:answer_option_id])
    return respond_saved if result.success?
    return redirect_to_upgrade(result) if daily_limit_reached?(result)

    # A late answer has just ended the exam; anything else leaves the student where they were.
    back = @exam.reload.status_completed? ? exam_path(@exam) : exam_question_path(@exam, @exam_question.position)
    redirect_to back, alert: result.errors.full_messages.to_sentence, status: :see_other
  end

  # The one-tap reason a wrong answer was wrong. Answered in place, so marking it never
  # scrolls the student away from the explanation they are reading.
  def update
    @answer = @exam_question.answer
    # Asking why an answer was wrong says it was wrong, so not before the answer is shown.
    return head(:not_found) if @answer.nil? || @answer.correct? || (@exam.feedback_at_end? && !@exam.status_completed?)

    saved = @answer.update(error_reason: params.expect(answer: [:error_reason])[:error_reason].presence)
    render partial: "exam_questions/triage", status: saved ? :ok : :unprocessable_content,
      locals: { answer: @answer, exam: @exam, exam_question: @exam_question }
  end

  private

  def set_exam_question
    @exam = Current.user.exams.find(params[:exam_id])
    @exam_question = @exam.exam_questions.find_by!(position: params[:question_position])
  end

  # One question at a time, the answer is explained on the question's own page. On the
  # single page the student stays where they are: the choice is saved in place and the
  # page only updates its count.
  def respond_saved
    return redirect_to(
      exam_question_path(@exam, @exam_question.position),
      status: :see_other
    ) if @exam.feedback_after_each?

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to exam_path(@exam, anchor: helpers.dom_id(@exam_question)), status: :see_other }
    end
  end
end
