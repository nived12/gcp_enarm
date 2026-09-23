# The review queue: every case that still needs a person, and the three things a person
# can do about one. Reading a case happens on the existing review screen, which each row
# links to, rather than on a second copy of it here.
#
# Flagging only takes a case away from students, so any reviewer may do it. Retiring
# and restoring decide what the bank holds, and restoring can put a case back in front of
# students, so both are the admin's — and restoring publishes only through
# Questions::Publisher, which applies the same rule it applies to every case.
module Admin
  class ClinicalCasesController < BaseController
    include Pagy::Method

    before_action :require_admin, only: :update, unless: -> { params[:transition] == "flag" }

    PER_PAGE = 20
    QUEUES = %w[reported flagged disputed unverified retired].freeze
    TRANSITIONS = { "flag" => "flagged", "retire" => "retired", "restore" => "draft" }.freeze

    helper_method :queue

    def index
      @counts = QUEUES.index_with { |name| cases_in(name).count }
      @total = ClinicalCase.in_review_queue.count
      @pagy, @cases = pagy(
        cases_in(queue).includes(:guideline, :topic).order(created_at: :desc, id: :desc), limit: PER_PAGE
      )
      @report_counts = QuestionReport.open_counts_by_case(@cases.map(&:id))
    end

    def update
      clinical_case = ClinicalCase.find(params[:id])
      status = TRANSITIONS.fetch(params[:transition]) { return head(:unprocessable_content) }

      clinical_case.update!(status: status)
      Questions::Publisher.call(cases: ClinicalCase.where(id: clinical_case.id)) if status == "draft"

      redirect_back_or_to admin_clinical_cases_path,
        notice: t(
          "admin.clinical_cases.done.#{params[:transition]}",
          status: t("admin.statuses.#{clinical_case.reload.status}")
        ),
        status: :see_other
    end

    private

    def queue
      params[:queue].presence_in(QUEUES)
    end

    def cases_in(name)
      case name
      when "reported" then ClinicalCase.in_review_queue.with_open_reports
      when "flagged" then ClinicalCase.status_flagged
      when "disputed" then ClinicalCase.in_review_queue.where(verification_verdict: %w[unsupported ambiguous])
      when "unverified" then ClinicalCase.in_review_queue.where(verification_verdict: nil)
      when "retired" then ClinicalCase.status_retired
      else ClinicalCase.in_review_queue
      end
    end
  end
end
