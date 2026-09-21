# The screen a doctor reviews generated cases on, before any of them reach a student.
#
# Phase 2's quality gate is a person reading vignettes, not a metric: every automated
# check — valid JSON, four options, one correct, a citation that survives the substring
# gate — passes at 100% on every model tested. What those checks cannot see is whether
# the distractors are plausible, which is the whole difference between a useful item and
# one that teaches nothing.
#
# So the flow is built for reading in sequence: the list orients, and the case page moves
# to the next one without going back.
#
# Pagy 43 puts its helpers on the paginator object rather than in the view, and `pagy`
# comes from Pagy::Method. The nav is built from @pagy's own attributes instead of its
# tag helpers, so the controls carry this app's tokens rather than Pagy's markup.
module Review
  class ClinicalCasesController < ApplicationController
    include Pagy::Method

    before_action :require_reviewer

    PER_PAGE = 10

    def index
      @pagy, @cases = pagy(ordered.includes(:guideline, :topic, :questions, :clinical_image), limit: PER_PAGE)
      @runs = GenerationRun.recent.limit(5)
    end

    def show
      @case = scope.includes(:clinical_image, questions: %i[answer_options recommendation])
                   .find(params[:id])
      @position = ordered.where(created_at: @case.created_at..).where.not(id: @case.id).count + 1
      @total = scope.count
      @previous = ordered.where(created_at: @case.created_at..).where.not(id: @case.id).last
      @next = ordered.where(created_at: ..@case.created_at).where.not(id: @case.id).first
    end

    private

    def scope
      cases = ClinicalCase.all
      cases = cases.where(generation_run_id: params[:run_id]) if params[:run_id].present?
      cases
    end

    # Newest first, with id as the tie-break: cases generated in the same batch share a
    # timestamp to the second, and without a stable second key "next" and "previous"
    # disagree with the list they came from.
    def ordered
      scope.order(created_at: :desc, id: :desc)
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
