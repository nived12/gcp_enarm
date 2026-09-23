# The next pearl for a student: one due for review first, most overdue first; then one
# they have never seen.
#
# New pearls come from the guidelines behind the cases the student missed, then from the
# ones behind cases they have met, then from the rest — the statements nearest to what
# they are working on. Current guidelines go before expired ones. Past that the order is a
# hash of the student and the statement: fixed for one student, different between them,
# with no randomness to make a session unrepeatable.
module Pearls
  class CardPicker < ApplicationService
    BATCH = 50

    def initialize(user)
      super()
      @user = user
    end

    def call
      success(due || fresh)
    end

    private

    attr_reader :user

    def due
      ReviewCard.where(user: user).pearls.due(user.study_date).order(:due_on, :id)
                .includes(recommendation: { guideline_section: :guideline })
                .lazy.filter_map { |card| Pearl.for(card.recommendation) }.first
    end

    def fresh
      (0..).step(BATCH).each do |offset|
        batch = unseen.offset(offset).limit(BATCH).to_a
        return nil if batch.empty?

        pearl = batch.lazy.filter_map { |recommendation| Pearl.for(recommendation) }.first
        return pearl if pearl
      end
    end

    def unseen
      Pearl.pool.where.not(id: ReviewCard.where(user: user).pearls.select(:recommendation_id))
           .includes(guideline_section: :guideline).order(priority)
    end

    def priority
      missed_cases = ReviewCard.where(user: user).cases.select(:clinical_case_id)
      seen_cases = ExamQuestion.joins(:exam).where(exams: { user_id: user.id }).select(:clinical_case_id)
      missed = ClinicalCase.where(id: missed_cases).select(:guideline_id)
      seen = ClinicalCase.where(id: seen_cases).select(:guideline_id)
      Arel.sql(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, Guideline.oldest_valid_year, user.id]))
        CASE WHEN guidelines.id IN (#{missed.to_sql}) THEN 0 WHEN guidelines.id IN (#{seen.to_sql}) THEN 1 ELSE 2 END,
        CASE WHEN guidelines.year >= ? THEN 0 ELSE 1 END,
        md5(? || '-' || recommendations.id)
      SQL
    end
  end
end
