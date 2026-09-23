module StudyPlans
  # Writes placed slots as plan days and their topics: two inserts rather than a few
  # hundred creates, since a year's plan is some three hundred days.
  module DayWriter
    def self.clear(days)
      StudyPlanDayTopic.where(study_plan_day_id: days.select(:id)).delete_all
      StudyPlanDay.where(id: days.select(:id)).delete_all
    end

    def self.write(plan, placed)
      return if placed.empty?

      now = Time.current
      rows = placed.map do |date, slot|
        {
          study_plan_id: plan.id, date: date, kind: slot.kind, pass_number: slot.pass_number,
          specialty_id: slot.specialty_id, exam_id: slot.exam_id, created_at: now, updated_at: now
        }
      end
      ids = StudyPlanDay.insert_all!(rows, returning: %w[id date]).to_h { |row| [row["date"].to_s, row["id"]] }

      topics = placed.flat_map do |date, slot|
        day_id = ids.fetch(date.to_s)
        slot.topic_ids.map.with_index(1) do |topic_id, position|
          { study_plan_day_id: day_id, topic_id: topic_id, position: position }
        end
      end
      StudyPlanDayTopic.insert_all!(topics) if topics.any?
    end
  end
end
