class AddRationaleVerdictToAnswerOptions < ActiveRecord::Migration[8.1]
  def change
    # The second model family's judgement of the rationale, and its reason. Null means
    # nobody has judged it yet, which is not the same as judging it sound.
    add_column :answer_options, :rationale_verdict, :string
    add_column :answer_options, :rationale_note, :text
  end
end
