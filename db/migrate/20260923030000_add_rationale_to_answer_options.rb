class AddRationaleToAnswerOptions < ActiveRecord::Migration[8.1]
  def change
    # Why this option is or is not the answer to this question, in a sentence or two.
    # A question's explanation says why the right answer is right; a student who chose
    # a distractor needs to know why theirs was wrong, which is usually a different fact.
    add_column :answer_options, :rationale, :text
  end
end
