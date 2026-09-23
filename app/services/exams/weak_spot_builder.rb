# A quiz drawn from the student's weak spots (Stats::WeakSpotCalculator): published cases
# from the topics where they do worse than their own average.
#
# The weaker the topic, the more of the quiz it gets — seats are dealt by the D'Hondt
# method on how far each topic sits below the student's mean, so the weakest topic leads
# without shutting the others out. Within a topic, cases the student has never met come
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
      @filters ||= { "interleave" => true, "topic_ids" => spots.map { |spot| spot.topic.id } }
    end

    def candidates
      ClinicalCase.status_published.where(topic_id: filters["topic_ids"]).joins(:questions)
                  .group(:id, :specialty_id, :topic_id).order(:id)
                  .pluck(:id, :specialty_id, Arel.sql("COUNT(questions.id)"), :topic_id)
    end

    def ordered(rows)
      queues = rows.shuffle(random: random).each_with_index
                   .sort_by { |(id, *), index| [familiarity(id), index] }.map(&:first)
                   .group_by(&:last)
      excess = spots.to_h { |spot| [spot.topic.id, spot.excess] }
      seats = Hash.new(0)
      dealt = []

      until queues.values.all?(&:empty?)
        topic_id = queues.keys.select { |id| queues[id].any? }.max_by { |id| [excess[id] / (seats[id] + 1), -id] }
        seats[topic_id] += 1
        dealt << queues[topic_id].shift.first(3)
      end
      dealt
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
