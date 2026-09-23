# Triage of what students sent through "Sugerir cambios". Open ones first; a reviewer
# reads the case on the review screen, acts on the case there, and closes the report here
# with a note saying what was done.
module Admin
  class QuestionReportsController < BaseController
    include Pagy::Method

    PER_PAGE = 20

    helper_method :filters

    def index
      reports = QuestionReport.includes(:user, :resolved_by, question: :clinical_case).recent
      reports = reports.where(status: filters[:filter_status]) unless filters[:filter_status] == "all"
      reports = reports.where(reason: filters[:reason]) if filters[:reason]
      reports = reports.joins(:question).where(questions: { clinical_case_id: filters[:case_id] }) if filters[:case_id]
      @counts = QuestionReport.group(:status).count
      @pagy, @reports = pagy(reports, limit: PER_PAGE)
    end

    def update
      report = QuestionReport.find(params[:id])
      closed = report.close(status: params[:status], note: params[:resolution_note], by: Current.user)

      flash[closed ? :notice : :alert] =
        closed ? t("admin.question_reports.done.#{report.status}") : t("admin.question_reports.not_closed")
      redirect_to admin_question_reports_path(filters), status: :see_other
    end

    private

    # Open by default: that is the work. Every link and form here carries the filters, so
    # closing a report leaves the reviewer on the same list.
    def filters
      @filters ||= {
        filter_status: params[:filter_status].presence_in([*QuestionReport.statuses.keys, "all"]) || "open",
        reason: params[:reason].presence_in(QuestionReport.reasons.keys),
        case_id: params[:case_id].presence&.to_i
      }.compact
    end
  end
end
