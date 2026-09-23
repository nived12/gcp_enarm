# The Dr. Re calendar: one plan per student, one row per day that has something on it, and
# the topics each of those days names.
#
# Rest days are not stored. They follow from the plan's template, and a stored row for
# every Sunday would have to be moved every time the plan is re-fitted.
#
# A day's quiz is the exam it launched, so "done" follows from that exam being completed
# rather than from a second counter kept beside it; `completed_at` is only for the days
# that have no quiz to finish (a reading day, a catch-up day).
class CreateStudyPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :study_plans do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.date :exam_date, null: false
      t.date :starts_on, null: false
      t.string :template, null: false
      t.timestamps
    end

    create_table :study_plan_days do |t|
      t.references :study_plan, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.string :kind, null: false
      t.integer :pass_number, null: false
      t.references :specialty, foreign_key: true
      t.references :exam, foreign_key: { on_delete: :nullify }
      t.datetime :completed_at
      t.timestamps
    end
    add_index :study_plan_days, %i[study_plan_id date], unique: true

    create_table :study_plan_day_topics do |t|
      t.references :study_plan_day, null: false, foreign_key: true, index: false
      t.references :topic, null: false, foreign_key: true
      t.integer :position, null: false
    end
    add_index :study_plan_day_topics, %i[study_plan_day_id topic_id], unique: true
  end
end
