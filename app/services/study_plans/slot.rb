module StudyPlans
  # A day's worth of plan before it has a date: what the Builder lays out and the Fitter
  # places. `exam_id` travels with a slot so a quiz already started survives a re-fit.
  Slot = Data.define(:kind, :pass_number, :specialty_id, :topic_ids, :exam_id) do
    def self.for(kind, pass_number, specialty_id = nil, topic_ids = [])
      new(kind: kind, pass_number: pass_number, specialty_id: specialty_id, topic_ids: topic_ids, exam_id: nil)
    end

    def self.from_day(day)
      new(
        kind: day.kind, pass_number: day.pass_number, specialty_id: day.specialty_id,
        topic_ids: day.day_topics.map(&:topic_id), exam_id: day.exam_id
      )
    end

    def topics? = kind == "topics"

    def merge(other)
      with(topic_ids: topic_ids + other.topic_ids, exam_id: exam_id || other.exam_id)
    end
  end
end
