class CreateExams < ActiveRecord::Migration[8.1]
  def change
    create_table :exams do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :mode, null: false
      t.string :status, null: false, default: "in_progress"

      # What was actually drawn, not what was asked for: exams take whole cases, so a
      # ten-question quiz can hold eleven, and a narrow filter can hold fewer.
      t.integer :question_count, null: false

      # Null means untimed. The exam-length modes carry the real exam's minute per item.
      t.integer :time_limit_seconds

      # Accumulated server-side across pauses. running_since is when the clock last
      # started and is null while it is stopped, so the time on the clock never depends
      # on how long a paused exam sat in a tab.
      t.integer :elapsed_seconds, null: false, default: 0
      t.datetime :running_since

      # A plain percentage, as CIFRHS reports it. Never weighted.
      t.decimal :score, precision: 5, scale: 2
      t.jsonb :filters, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :exams, %i[user_id status]

    create_table :exam_questions do |t|
      t.references :exam, null: false, foreign_key: true, index: false
      t.references :question, null: false, foreign_key: true
      t.references :clinical_case, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :exam_questions, %i[exam_id position], unique: true
    add_index :exam_questions, %i[exam_id question_id], unique: true

    create_table :answers do |t|
      t.references :exam_question, null: false, foreign_key: true, index: { unique: true }

      # Null means the student left it blank.
      t.references :answer_option, foreign_key: true

      # Copied at answer time on purpose: a flagged question's correct option can change
      # later, and a finished exam's score must not move with it.
      t.boolean :correct, null: false, default: false
      t.integer :seconds_spent, null: false, default: 0
      t.datetime :answered_at, null: false

      # The student's own one-tap account of why a wrong answer was wrong. Null means
      # they did not say, which is not the same as "did not know".
      t.string :error_reason

      t.timestamps
    end

    add_index :answers, :answered_at
  end
end
