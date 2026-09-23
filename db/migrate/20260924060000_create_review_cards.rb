# One student's spaced-repetition schedule for one thing worth seeing again: a clinical
# case they missed, or a guideline statement studied as a pearl. Both run on the same
# SM-2 scheduler, so they share a table.
#
# Two foreign keys rather than a polymorphic pair, so the database removes a card with
# what it points at: a reparse deletes the statements whose text did not survive, and a
# card left pointing at nothing would break the deck.
class CreateReviewCards < ActiveRecord::Migration[8.1]
  def change
    create_table :review_cards do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :clinical_case, foreign_key: { on_delete: :cascade }
      t.references :recommendation, foreign_key: { on_delete: :cascade }
      t.decimal :ease_factor, precision: 4, scale: 2, null: false, default: 2.5
      t.integer :interval_days, null: false, default: 0
      t.integer :repetitions, null: false, default: 0
      t.integer :lapses, null: false, default: 0
      t.integer :reviews_count, null: false, default: 0
      t.date :due_on, null: false
      t.date :last_reviewed_on
      t.timestamps
    end

    add_index :review_cards, %i[user_id clinical_case_id], unique: true, where: "clinical_case_id IS NOT NULL"
    add_index :review_cards, %i[user_id recommendation_id], unique: true, where: "recommendation_id IS NOT NULL"
    add_index :review_cards, %i[user_id due_on]
    add_check_constraint :review_cards, "num_nonnulls(clinical_case_id, recommendation_id) = 1",
      name: "review_cards_one_subject"
  end
end
