# Re-files generated cases under their guideline's current main topic and its specialty.
#
# A case takes its topic when it is written, but the taxonomy keeps improving after that.
# Run this after taxonomy:seed and gpc:link so the filters and statistics describe the
# cases by what they are about now, without paying to write them again.
module Questions
  class Refiler < ApplicationService
    def call
      moved = 0

      ClinicalCase.where.not(guideline_id: nil).includes(:guideline).find_each do |kase|
        topic = main_topics[kase.guideline_id] ||= kase.guideline.main_topic
        next if kase.topic_id == topic&.id

        kase.update!(topic: topic, specialty: topic&.branch&.specialty)
        moved += 1
      end

      success(moved: moved)
    end

    private

    def main_topics
      @main_topics ||= {}
    end
  end
end
