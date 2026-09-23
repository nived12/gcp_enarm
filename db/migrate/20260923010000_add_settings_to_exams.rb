class AddSettingsToExams < ActiveRecord::Migration[8.1]
  def change
    # Chosen by the student when the exam is built, and kept on the row: a sitting lasts
    # hours, survives pauses and reloads, and the server enforces the clock from it.
    add_column :exams, :feedback_timing, :string, null: false, default: "after_each"

    # The pace the student chose. The limit itself stays in time_limit_seconds, for the
    # whole sitting: the real exam gives a total, never a per-question budget.
    add_column :exams, :seconds_per_question, :integer
  end
end
