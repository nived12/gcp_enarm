# Whether the corpus is fit to generate from: which guidelines came in, how many yielded
# statements a question can cite, and how the bank those statements produced is spread.
module Admin
  class IngestionController < BaseController
    before_action :require_admin

    def show
      with_statements = Guideline.where(id: GuidelineSection.joins(:recommendations).select(:guideline_id))
      @guidelines = {
        total: Guideline.count, with_statements: with_statements.count,
        generatable: Guideline.generatable.count, current: Guideline.current.count,
        expired: Guideline.expired.count, undated: Guideline.undated.count
      }
      @by_source = Guideline.group(:source).count
      @with_statements_by_source = with_statements.group(:source).count
      @recommendations = Recommendation.count
      @case_statuses = ClinicalCase.group(:status).count
      @specialties = Specialty.in_reading_order
      @cases_by_specialty = ClinicalCase.group(:specialty_id).count
      @published_by_specialty = ClinicalCase.status_published.group(:specialty_id).count
    end
  end
end
