# Walks the generatable corpus a window of statements at a time, handing each window to
# Questions::CaseGenerator, and stops at a number of calls or at a spending cap. The order
# of the windows is Questions::WindowPlan's.
#
# A window is made of statements no question cites yet, so running it again continues
# where the last run stopped instead of paying for the same cases twice. A statement the
# model was shown and did not use comes round again in a later window.
#
# It also stops after a run of failed calls. One failure is the model's; several in a row
# are the provider — a rate limit, an outage, an exhausted key — and every call after
# that would fail the same way.
module Questions
  class GenerationRunner < ApplicationService
    FAILURES_IN_A_ROW = 5

    def initialize(run:, calls:, budget_usd: nil, guidelines: Guideline.generatable, order: "newest",
                   specialty: nil, on_progress: nil)
      super()
      @run = run
      @calls = calls
      @budget_usd = budget_usd
      @plan = WindowPlan.new(guidelines, order: order, specialty: specialty)
      @on_progress = on_progress
    end

    def call
      provider = Llm::Provider.for(:generator)
      if budget_usd && !provider.priced?
        return failure("No conozco el precio de #{provider}; corre sin tope o agrega su precio a Llm::Provider")
      end

      counts = { calls: 0, cases: 0, rejected: 0, failed: 0 }
      planned = plan.windows.first(calls)
      @planned = planned.size
      @failures_in_a_row = 0
      stopped = planned.each_with_index do |(guideline, recommendations), index|
        break :budget if spent?
        break :failures if @failures_in_a_row >= FAILURES_IN_A_ROW

        generate(guideline, recommendations, index, counts)
      end

      success(
        counts.merge(
          stopped_at_budget: stopped == :budget, stopped_after_failures: stopped == :failures,
          cost_usd: run.reload.cost_usd.to_f
        )
      )
    end

    private

    attr_reader :run, :calls, :budget_usd, :plan, :on_progress

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
        @failures_in_a_row = 0
      else
        counts[:failed] += 1
        @failures_in_a_row += 1
      end
      report(guideline, options, result)
    end

    def report(guideline, options, result)
      return if on_progress.nil?

      tags = options.values_at(:detail, :locale).join("/")
      state = result.success? ? "#{result.payload[:cases].size} casos" : result.errors.full_messages.first
      on_progress.call("#{guideline.catalog_key} [#{tags}] #{state}")
    end

    # A fixed rotation rather than a random draw, so a run is reproducible. Long vignettes
    # alternate with short ones, and English lands on a schedule.
    #
    # ENGLISH_SHARE is right for the full corpus and wrong for a small batch: at 8% the
    # first English case falls on the 14th call, so a smaller sample gets none and nobody
    # reviewing it ever sees one. Below that the last call made is forced to English —
    # the sample is deliberately over-representative, which is what a sample is for.
    def rotation(index)
      english_every = (1 / CaseGenerator::ENGLISH_SHARE).round
      forced_english = @planned < english_every ? @planned - 1 : nil
      scheduled = index.positive? && (index % english_every).zero?

      {
        detail: Prompt.detail_for(index),
        locale: index == forced_english || scheduled ? "en" : "es"
      }
    end
  end
end
