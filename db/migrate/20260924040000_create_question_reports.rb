class CreateQuestionReports < ActiveRecord::Migration[8.1]
  def change
    create_table :question_reports do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :question, null: false, foreign_key: true
      t.string :reason, null: false
      t.text :comment
      t.string :status, null: false, default: "open"
      t.text :resolution_note
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at

      t.timestamps
    end

    # One open report per student per question: a second tap on "Enviar" must not file
    # the same complaint twice. Once it is closed, the student may report it again.
    add_index :question_reports, %i[user_id question_id], unique: true, where: "status = 'open'",
      name: "index_question_reports_one_open_per_user"
    add_index :question_reports, %i[status created_at]
  end
end
