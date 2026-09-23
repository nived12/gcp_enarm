# The topics where the student is doing worse than their own average, weakest first.
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
# * picking the same wrong option on a question they have already missed that way is a
#   settled misconception rather than a slip, and counts half again;
# * recent answers count more than old ones, halving every three weeks, so a topic they
#   have since studied stops being named;
# * few questions say little, so each topic is pulled toward the student's mean by a few
#   questions' worth of it before it is compared — two unlucky misses do not make a weak
#   spot, and a topic with many answers is judged on its own.
module Stats
  class WeakSpotCalculator < ApplicationService
    MINIMUM_ANSWERED = 10
    MINIMUM_TOPIC_QUESTIONS = 2
    HALF_LIFE_DAYS = 21.0
    PRIOR_QUESTIONS = 3.0
    SLIP_GAP = 0.25
    REPEATED_DISTRACTOR_WEIGHT = 1.5
    KNOWLEDGE_REASONS = %w[did_not_know confused_diagnoses].freeze
    SLIP_REASONS = %w[misread_case ran_out_of_time].freeze

    Spot = Data.define(:topic, :gap, :excess, :asked)
    Result = Data.define(:spots, :mean_gap, :asked) do
      def enough_data? = asked >= MINIMUM_ANSWERED
    end

    Row = Data.define(:topic_id, :question_id, :correct, :reason, :option_id, :at)

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
      ExamQuestion.joins(:exam, :clinical_case).left_joins(:answer)
                  .where(exams: { id: user.exams.kept.select(:id) })
                  .where("answers.id IS NOT NULL OR exams.status = 'completed'")
                  .where.not(clinical_cases: { topic_id: nil })
                  .pluck(
                    "clinical_cases.topic_id", :question_id, "answers.correct", "answers.error_reason",
                    "answers.answer_option_id", Arel.sql("COALESCE(answers.answered_at, exams.completed_at)")
                  )
                  .map { |values| Row.new(*values) }
    end

    # [topic_id, weight, gap] for each question counted.
    def score(rows)
      unknown = unknown_gap(rows)
      repeated = repeated_distractors(rows)

      rows.map do |row|
        weight = 0.5**(((now - row.at) / 1.day) / HALF_LIFE_DAYS)
        weight *= REPEATED_DISTRACTOR_WEIGHT if repeated.include?(row)
        [row.topic_id, weight, gap(row, unknown)]
      end
    end

    def gap(row, unknown)
      return 0.0 if row.correct
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
      scored.sum { |_topic, weight, gap| weight * gap } / scored.sum { |_topic, weight, _gap| weight }
    end

    def spots(scored, mean)
      by_topic = scored.group_by(&:first).select { |_topic_id, rows| rows.size >= MINIMUM_TOPIC_QUESTIONS }
      gaps = by_topic.transform_values do |rows|
        (rows.sum { |_topic, weight, gap| weight * gap } + (PRIOR_QUESTIONS * mean)) /
          (rows.sum { |_topic, weight, _gap| weight } + PRIOR_QUESTIONS)
      end
      weak = gaps.select { |_topic_id, gap| gap > mean }
      topics = Topic.where(id: weak.keys).index_by(&:id)

      weak.sort_by { |topic_id, gap| [-gap, topic_id] }.map do |topic_id, gap|
        Spot.new(topic: topics.fetch(topic_id), gap: gap, excess: gap - mean, asked: by_topic[topic_id].size)
      end
    end
  end
end
