# One row per student per local study day, written as answers arrive. The streak is
# computed from these rows, never kept as a counter on the user: a counter drifts the
# first time a write is retried or a time zone changes.
#
# There is no `frozen` column. Whether a missed day was covered by a streak freeze follows
# from the days around it, so it is derived with the streak rather than stored beside it.
class CreateStudyDays < ActiveRecord::Migration[8.1]
  def change
    create_table :study_days do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.integer :questions_answered, null: false, default: 0
      t.integer :pearls_reviewed, null: false, default: 0
      t.timestamps
    end
    add_index :study_days, %i[user_id date], unique: true
  end
end
