# Builds a student's calendar from today to the exam, in Dr. Re's shape: the syllabus
# walked specialty by specialty, each study day naming two or three topics, repeated in
# up to three passes that each run faster than the one before.
#
# Every topic is scheduled, whether or not the bank has cases on it yet. The calendar is
# the syllabus, and the bank grows under it: a topic without cases is a reading day
# today and a quiz day once its first case is published, with nothing to regenerate.
module StudyPlans
  class Builder < ApplicationService
    # Dr. Re's temario opens with surgery and closes with internal medicine. The three
    # transversal settings follow the four troncales, in their own order.
    CANONICAL_ORDER = %w[cirugia-general gineco-obstetricia pediatria medicina-interna].freeze

    # How the study days split between passes: the first reading is the long one and the
    # last a sweep.
    PASS_SHARES = { 3 => [5, 3, 2], 2 => [3, 2], 1 => [1] }.freeze

    # The most topics a day may carry in each pass before the plan drops a pass instead.
    # Four is already a heavy first reading; a third pass is a sweep and can go fast.
    MOST_TOPICS_A_DAY = [4, 8, 12].freeze

    Block = Data.define(:specialty_id, :topic_ids)

    def initialize(user:, exam_date:, template:, today: user.study_date)
      super()
      @user = user
      @exam_date = exam_date
      @template = template
      @today = today
    end

    def call
      plan = user.study_plan || user.build_study_plan
      plan.assign_attributes(exam_date: exam_date, template: template, starts_on: today)
      return failure(plan.errors.full_messages.to_sentence) unless plan.valid?
      return failure(I18n.t("study_plans.builder.no_topics")) if blocks.empty?

      dates = plan.study_dates(today)
      StudyPlan.transaction do
        plan.save!
        DayWriter.clear(plan.days)
        DayWriter.write(plan, Fitter.fit(slots(dates.size), dates))
      end
      success(plan: plan.reload)
    end

    def context_for_logging
      { user_id: user.id, exam_date: exam_date, template: template }
    end

    private

    attr_reader :user, :exam_date, :template, :today

    def blocks
      @blocks ||= begin
        specialties = Specialty.in_reading_order.to_a
        ordered = specialties.sort_by.with_index { |s, i| [CANONICAL_ORDER.index(s.slug) || CANONICAL_ORDER.size, i] }
        topics = Topic.joins(:branch).order("branches.position", :position, :id).pluck("branches.specialty_id", :id)
                      .group_by(&:first)
        ordered.filter_map { |s| Block.new(s.id, topics[s.id].map(&:last)) if topics[s.id] }
      end
    end

    def topic_count
      blocks.sum { |block| block.topic_ids.size }
    end

    def slots(study_days)
      passes = pass_count(study_days)
      split(study_days, PASS_SHARES.fetch(passes)).flat_map.with_index(1) do |days, pass|
        pass_slots(pass, days, last: pass == passes)
      end
    end

    # The most passes that keep every one of them under its daily ceiling.
    def pass_count(study_days)
      [3, 2].find do |passes|
        split(study_days, PASS_SHARES.fetch(passes)).each_with_index.all? do |days, index|
          topic_days(days, last: index == passes - 1) >= (topic_count / MOST_TOPICS_A_DAY[index].to_f).ceil
        end
      end || 1
    end

    # Rounded down, with what rounding leaves over going to the first pass.
    def split(total, shares)
      parts = shares.map { |share| total * share / shares.sum }
      parts[0] += total - parts.sum
      parts
    end

    # Each specialty ends in a workshop and, before the last pass, a catch-up day; each
    # pass ends in a review and a simulacro.
    def closing_days(last)
      (blocks.size * (last ? 1 : 2)) + 2
    end

    def topic_days(days, last:)
      days - closing_days(last)
    end

    def pass_slots(pass, days, last:)
      body = blocks.zip(spread(topic_days(days, last: last))).flat_map do |block, count|
        chunk(block.topic_ids, count).map { |ids| Slot.for("topics", pass, block.specialty_id, ids) } +
          [Slot.for("case_workshop", pass, block.specialty_id)] +
          (last ? [] : [Slot.for("catch_up", pass)])
      end
      # A pass with more days than topics fills the rest with review rather than leave
      # a day empty: more questions is never the wrong use of a spare day.
      reviews = [days - body.size - 1, 1].max
      body + Array.new(reviews) { Slot.for("review", pass) } + [Slot.for("assessment", pass)]
    end

    # Days for each specialty: one each to start, then each further day to whichever
    # specialty has the most topics per day, so every day carries about the same load.
    # A specialty never gets more days than it has topics.
    def spread(total)
      counts = Array.new(blocks.size, 1)
      (total - blocks.size).times do
        open = blocks.each_index.select { |i| counts[i] < blocks[i].topic_ids.size }
        break if open.empty?

        counts[open.max_by { |i| [blocks[i].topic_ids.size.fdiv(counts[i]), -i] }] += 1
      end
      counts
    end

    def chunk(ids, count)
      base, extra = ids.size.divmod(count)
      offset = 0
      Array.new(count) do |i|
        size = base + (i < extra ? 1 : 0)
        ids[offset, size].tap { offset += size }
      end
    end
  end
end
