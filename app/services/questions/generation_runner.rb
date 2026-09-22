# Walks the generatable corpus a window of statements at a time, handing each window to
# Questions::CaseGenerator, and stops at a number of calls or at a spending cap.
#
# Breadth first: every guideline's first window before any guideline's second, so a run
# stopped early — by the cap, a crash, or on purpose — has touched the whole syllabus
# thinly rather than a few topics deeply.
#
# A window is made of statements no question cites yet, so running it again continues
# where the last run stopped instead of paying for the same cases twice. A statement the
# model was shown and did not use comes round again in a later window.
module Questions
  class GenerationRunner < ApplicationService
    def initialize(run:, calls:, budget_usd: nil, guidelines: Guideline.generatable, on_progress: nil)
      super()
      @run = run
      @calls = calls
      @budget_usd = budget_usd
      @guidelines = guidelines
      @on_progress = on_progress
    end

    def call
      provider = Llm::Provider.for(:generator)
      if budget_usd && !provider.priced?
        return failure("No conozco el precio de #{provider}; corre sin tope o agrega su precio a Llm::Provider")
      end

      counts = Hash.new(0)
      planned = windows.first(calls)
      @planned = planned.size
      planned.each_with_index do |(guideline, recommendations), index|
        break counts[:stopped_at_budget] = 1 if spent?

        generate(guideline, recommendations, index, counts)
      end

      success(counts.merge(cost_usd: run.reload.cost_usd.to_f))
    end

    private

    attr_reader :run, :calls, :budget_usd, :guidelines, :on_progress

    def spent?
      budget_usd && run.reload.cost_usd >= budget_usd
    end

    def generate(guideline, recommendations, index, counts)
      options = rotation(index)
      result = CaseGenerator.call(guideline, run: run, recommendations: recommendations, **options)
      counts[:calls] += 1

      if result.success?
        counts[:cases] += result.payload[:cases].size
        counts[:rejected] += result.payload[:rejected]
      else
        counts[:failed] += 1
      end
      report(guideline, options, result)
    end

    def report(guideline, options, result)
      return if on_progress.nil?

      tags = [options[:detail], options[:locale], ("figura" if options[:with_image])].compact.join("/")
      state = result.success? ? "#{result.payload[:cases].size} casos" : result.errors.full_messages.first
      on_progress.call("#{guideline.catalog_key} [#{tags}] #{state}")
    end

    # Current guidelines first, since the plan prefers them; within a pass, newest first.
    def windows
      by_guideline = uncited.group_by(&:source_guideline_id)
      ordered = guidelines.where(id: by_guideline.keys).order(Arel.sql("year DESC NULLS LAST"), :catalog_key)
      slices = ordered.map { |g| [g, by_guideline[g.id].each_slice(CaseGenerator::RECOMMENDATIONS_PER_CALL).to_a] }

      deepest = slices.map { |_, windows| windows.size }.max.to_i
      (0...deepest).flat_map do |pass|
        slices.filter_map { |guideline, windows| [guideline, windows[pass]] if windows[pass] }
      end
    end

    def uncited
      Recommendation.actionable
                    .where(guideline_sections: { guideline_id: guidelines.select(:id) })
                    .where.not(id: Question.where.not(recommendation_id: nil).select(:recommendation_id))
                    .select("recommendations.*, guideline_sections.guideline_id AS source_guideline_id")
                    .order(:id)
    end

    # A fixed rotation rather than a random draw, so a run is reproducible. Long vignettes
    # alternate with short ones, English lands on a schedule, and so do figures.
    #
    # ENGLISH_SHARE is right for the full corpus and wrong for a small batch: at 8% the
    # first English case falls on the 14th call, so a smaller sample gets none and nobody
    # reviewing it ever sees one. Below that the last call made is forced to English —
    # the sample is deliberately over-representative, which is what a sample is for.
    # Figures are over-represented in a small batch for the same reason.
    def rotation(index)
      english_every = (1 / CaseGenerator::ENGLISH_SHARE).round
      image_every = (1 / CaseGenerator::IMAGE_SHARE).round
      forced_english = @planned < english_every ? @planned - 1 : nil
      scheduled = index.positive? && (index % english_every).zero?

      {
        detail: index.even? ? :full_workup : :focused,
        locale: index == forced_english || scheduled ? "en" : "es",
        with_image: (index % image_every).zero?
      }
    end
  end
end
