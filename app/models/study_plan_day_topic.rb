# A topic named on a study plan day, in the order the day lists them.
class StudyPlanDayTopic < ApplicationRecord
  belongs_to :study_plan_day
  belongs_to :topic
end
