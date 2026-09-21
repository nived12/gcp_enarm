# The screen a doctor reviews generated cases on, before any of them reach a student.
#
# Phase 2's quality gate is a person reading vignettes, not a metric: every automated
# check — valid JSON, four options, one correct, a citation that survives the substring
# gate — passes at 100% on every model tested. What those checks cannot see is whether
# the distractors are plausible, which is the whole difference between a useful item and
# one that teaches nothing.
module Review
  class ClinicalCasesController < ApplicationController
    before_action :require_reviewer

    PER_PAGE = 20

    def index
      @runs = GenerationRun.recent.limit(10)
      @cases = scope.includes(:guideline, :topic, questions: %i[answer_options recommendation])
                    .order(created_at: :desc)
                    .limit(PER_PAGE)
    end

    def show
      @case = scope.includes(questions: %i[answer_options recommendation]).find(params[:id])
    end

    private

    def scope
      cases = ClinicalCase.all
      cases = cases.where(generation_run_id: params[:run_id]) if params[:run_id].present?
      cases
    end

    # Reviewers and admins only. Generated-but-unreviewed cases are drafts, and a student
    # who stumbled onto them would be studying from unverified medicine.
    #
    # Current.user is never nil here: Authentication has already redirected anyone who is
    # not signed in, so guarding against it again would only add a branch nothing reaches.
    def require_reviewer
      return if Current.user.role_admin? || Current.user.role_reviewer?

      redirect_to root_path, alert: t("review.denied")
    end
  end
end
