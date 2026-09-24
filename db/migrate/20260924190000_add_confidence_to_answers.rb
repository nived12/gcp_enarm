# How sure the student said they were, chosen with the answer and before any feedback.
# Optional: most answers will carry none, which means only that they did not say.
class AddConfidenceToAnswers < ActiveRecord::Migration[8.1]
  def change
    add_column :answers, :confidence, :string
  end
end
