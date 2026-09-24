# A quiz drawn from the student's weak spots (Stats::WeakSpotCalculator): published cases
# from the topics and settings where they do worse than their own average. A setting
# draws its whole area (`ClinicalCase.in_area`).
#
# The weaker the spot, the more of the quiz it gets — seats are dealt by the D'Hondt
# method on how far each spot sits below the student's mean, so the weakest spot leads
# without shutting the others out. A case in a weak topic and a weak setting is dealt
# once, by the weaker of the two. Within a spot, cases the student has never met come
# first (can they use it on a new patient?), then the ones they missed, and last the
# ones they already got right.
module Exams
  class WeakSpotBuilder < Builder
    def call
      return failure(I18n.t("weak_spots.none")) if spots.empty?

      super
    end

    private

    def spots
      @spots ||= Stats::WeakSpotCalculator.call(user).payload.spots
    end

    def filters
      @filters ||= {
        "interleave" => true,
        "topic_ids" => spots.filter_map { |spot| spot.topic&.id },
        "setting_ids" => spots.filter_map { |spot| spot.setting&.id }
      }.compact_blank
    end

    def candidates
      topic_ids, setting_ids = filters.values_at("topic_ids", "setting_ids").map { |ids| Array(ids) }
      cases = ClinicalCase.status_published
      cases.where(topic_id: topic_ids).or(cases.in_area(setting_ids)).joins(:questions)
           .group(:id, :specialty_id, :topic_id, :setting_id).order(:id)
           .pluck(:id, :specialty_id, Arel.sql("COUNT(questions.id)"), :topic_id, :setting_id)
    end

    def ordered(rows)
      queues = rows.shuffle(random: random).each_with_index
                   .sort_by { |(id, *), index| [familiarity(id), index] }.map(&:first)
                   .group_by { |row| weakest_spot(row) }
      seats = Hash.new(0)
      dealt = []

      until queues.values.all?(&:empty?)
        spot = queues.keys.select { |key| queues[key].any? }
                     .max_by { |key| [key.excess / (seats[key] + 1), -spots.index(key)] }
        seats[spot] += 1
        dealt << queues[spot].shift.first(3)
      end
      dealt
    end

    # Spots come weakest first, so the first one the case belongs to is the weakest.
    def weakest_spot(row)
      _id, specialty_id, _count, topic_id, setting_id = row
      spots.find do |spot|
        spot.topic ? spot.topic.id == topic_id : [specialty_id, setting_id].include?(spot.setting.id)
      end
    end

    def familiarity(case_id)
      return 0 unless answered.key?(case_id)

      answered[case_id] ? 2 : 1
    end

    # Case id => whether every answer the student gave on it was right.
    def answered
      @answered ||= ExamQuestion.answered_by(user).group(:clinical_case_id)
                                .pluck(:clinical_case_id, Arel.sql("BOOL_AND(answers.correct)")).to_h
    end
  end
end
