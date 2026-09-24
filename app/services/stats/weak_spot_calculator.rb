# The topics and settings where the student is doing worse than their own average,
# weakest first.
#
# Measured against themselves rather than a cutoff: a student at 55% overall and one at
# 85% both have topics dragging them down, and those are the topics worth practising.
# The questions counted are the ones Stats::PerformanceCalculator counts — every answered
# one, plus the blanks of a finished exam — from exams the student kept.
#
# Each question contributes a gap between 0 (right) and 1 (a miss that shows something
# not known), and the weighting follows what the miss says:
#
# * why it was missed is the student's own account (Answer#error_reason). Not knowing and
#   confusing diagnoses are gaps in knowledge and weigh fully. Misreading the case and
#   running out of time are not — the topic is not where the work is — so they weigh a
#   quarter;
# * a miss with no reason, or a blank, is unknown — never taken as not knowing. It weighs
#   what this student's own reasons say a miss usually is: the share of their explained
#   misses that were knowledge gaps, with one pseudo-count on each side so a student who
#   has explained nothing sits at the middle;
# * how sure they said they were (Answer#confidence) weighs as Reviews::CaseScheduler
#   grades it: right but unsure counts as a slip and right by guessing as an unexplained
#   miss, while a miss they were sure of is a misconception. Not saying changes nothing;
# * picking the same wrong option on a question they have already missed that way is a
#   settled misconception rather than a slip, and a misconception counts half again;
# * recent answers count more than old ones, halving every three weeks, so a topic they
#   have since studied stops being named;
# * few questions say little, so each topic is pulled toward the student's mean by a few
#   questions' worth of it before it is compared — two unlucky misses do not make a weak
#   spot, and a topic with many answers is judged on its own.
#
# A setting (Urgencias, Medicina Familiar, Salud Pública) is an area as everywhere else
# (`ClinicalCase.in_area`): the questions of cases about it or set in it. It is judged
# beside the topics, so a question can count toward its topic and its setting, as the
# rows of /stats do; the mean every area is compared with still counts each question once.
module Stats
  class WeakSpotCalculator < ApplicationService
    MINIMUM_ANSWERED = 10
    MINIMUM_AREA_QUESTIONS = 2
    HALF_LIFE_DAYS = 21.0
    PRIOR_QUESTIONS = 3.0
    SLIP_GAP = 0.25
    MISCONCEPTION_WEIGHT = 1.5
    KNOWLEDGE_REASONS = %w[did_not_know confused_diagnoses].freeze
    SLIP_REASONS = %w[misread_case ran_out_of_time].freeze

    # A spot is a topic or a setting, never both.
    Spot = Data.define(:topic, :setting, :gap, :excess, :asked) do
      def area = topic || setting
    end
    Result = Data.define(:spots, :mean_gap, :asked) do
      def enough_data? = asked >= MINIMUM_ANSWERED
    end

    Row = Data.define(:topic_id, :setting_ids, :question_id, :correct, :reason, :confidence, :option_id, :at)

    def initialize(user, now: Time.current)
      super()
      @user = user
      @now = now
    end

    def call
      rows = load_rows
      return success(Result.new(spots: [], mean_gap: nil, asked: rows.size)) if rows.size < MINIMUM_ANSWERED

      scored = score(rows)
      mean = weighted_mean(scored)
      success(Result.new(spots: spots(scored, mean), mean_gap: mean, asked: rows.size))
    end

    private

    attr_reader :user, :now

    def load_rows
      settings = Specialty.kind_cross_cutting.ids
      ExamQuestion.joins(:exam, :clinical_case).left_joins(:answer)
                  .where(exams: { id: user.exams.kept.select(:id) })
                  .where("answers.id IS NOT NULL OR exams.status = 'completed'")
                  .where.not(clinical_cases: { topic_id: nil })
                  .pluck(
                    "clinical_cases.topic_id", "clinical_cases.specialty_id", "clinical_cases.setting_id",
                    :question_id, "answers.correct", "answers.error_reason", "answers.confidence",
                    "answers.answer_option_id", Arel.sql("COALESCE(answers.answered_at, exams.completed_at)")
                  )
                  .map do |topic_id, specialty_id, setting_id, *values|
                    Row.new(topic_id, [specialty_id, setting_id].uniq & settings, *values)
                  end
    end

    # [areas, weight, gap] for each question counted, an area being [:topic, id] or
    # [:setting, id].
    def score(rows)
      unknown = unknown_gap(rows)
      repeated = repeated_distractors(rows)

      rows.map do |row|
        weight = 0.5**(((now - row.at) / 1.day) / HALF_LIFE_DAYS)
        weight *= MISCONCEPTION_WEIGHT if repeated.include?(row) || (!row.correct && row.confidence == "sure")
        areas = [[:topic, row.topic_id], *row.setting_ids.map { |id| [:setting, id] }]
        [areas, weight, gap(row, unknown)]
      end
    end

    def gap(row, unknown)
      return { "unsure" => SLIP_GAP, "guess" => unknown }.fetch(row.confidence, 0.0) if row.correct
      return 1.0 if KNOWLEDGE_REASONS.include?(row.reason)
      return SLIP_GAP if SLIP_REASONS.include?(row.reason)

      unknown
    end

    def unknown_gap(rows)
      explained = rows.map(&:reason).compact
      knowledge_share = (explained.count { |reason| KNOWLEDGE_REASONS.include?(reason) } + 1.0) / (explained.size + 2)
      knowledge_share + ((1 - knowledge_share) * SLIP_GAP)
    end

    # Misses that repeat a wrong option this student already chose on the same question.
    def repeated_distractors(rows)
      rows.select(&:option_id).reject(&:correct).group_by(&:question_id).values.flat_map do |misses|
        misses.sort_by(&:at).each_with_object([[], Set.new]) do |row, (repeats, chosen)|
          repeats << row if chosen.include?(row.option_id)
          chosen << row.option_id
        end.first
      end.to_set
    end

    def weighted_mean(scored)
      scored.sum { |_areas, weight, gap| weight * gap } / scored.sum { |_areas, weight, _gap| weight }
    end

    def spots(scored, mean)
      by_area = scored.flat_map { |areas, weight, gap| areas.map { |area| [area, weight, gap] } }
                      .group_by(&:first).select { |_area, rows| rows.size >= MINIMUM_AREA_QUESTIONS }
      gaps = by_area.transform_values do |rows|
        (rows.sum { |_area, weight, gap| weight * gap } + (PRIOR_QUESTIONS * mean)) /
          (rows.sum { |_area, weight, _gap| weight } + PRIOR_QUESTIONS)
      end
      weak = gaps.select { |_area, gap| gap > mean }.sort_by { |area, gap| [-gap, area] }
      records = { topic: Topic, setting: Specialty }.to_h do |kind, model|
        [kind, model.where(id: weak.filter_map { |(area_kind, id), _gap| id if area_kind == kind }).index_by(&:id)]
      end

      weak.map do |(kind, id), gap|
        Spot.new(
          topic: nil, setting: nil, kind => records[kind].fetch(id),
          gap: gap, excess: gap - mean, asked: by_area[[kind, id]].size
        )
      end
    end
  end
end
