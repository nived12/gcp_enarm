module Admin
  class DashboardController < BaseController
    def show
      @open_reports = QuestionReport.status_open.count
      @queue = ClinicalCase.in_review_queue.count
      @spend = GenerationRun.sum(:cost_usd) if Current.user.role_admin?
    end
  end
end
