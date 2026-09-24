# What a student asked to be reminded of, and when. Every reminder is opt-in, so a row
# that does not exist means the same as one with everything off.
class CreateReminderPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :reminder_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :study_days, null: false, default: false
      t.boolean :streak_at_risk, null: false, default: false
      t.boolean :exam_countdown, null: false, default: false
      t.boolean :by_email, null: false, default: false
      t.integer :minute_of_day, null: false, default: 480
      t.timestamps
    end
  end
end
