# "Sugerir cambios": a student reporting a question they have already seen explained.
#
# Answered in place, inside the question page's frame, so filing a report never moves the
# student away from the explanation they were reading.
class QuestionReportsController < ApplicationController
  def create
    exam = Current.user.exams.find(params[:exam_id])
    exam_question = exam.exam_questions.find_by!(position: params[:question_position])
    # A report is about a question and its answer, so only once the answer is on screen:
    # before that, it would tell the student something is wrong with it.
    return head(:not_found) unless exam_question.revealed?

    report = Current.user.question_reports.status_open.find_or_initialize_by(question: exam_question.question)
    saved = report.persisted? || report.update(report_params)
    render partial: "question_reports/panel", status: saved ? :ok : :unprocessable_content,
      locals: { exam: exam, exam_question: exam_question, report: report }
  end

  private

  def report_params
    params.fetch(:question_report, {}).permit(:reason, :comment)
  end
end
