class CreateRecommendations < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendations do |t|
      t.references :guideline_section, null: false, foreign_key: true

      t.text :text, null: false

      # The grading strip exactly as published, e.g. "1++ NICE Hong K, 2021". Kept
      # verbatim because the three fields below are a best-effort split of a string
      # the authors write by hand and inconsistently; label is what a question cites.
      t.string :label, null: false
      t.string :grade
      t.string :scale
      t.string :citation

      t.integer :position, null: false

      t.timestamps
    end

    add_index :recommendations, [:guideline_section_id, :position], unique: true
    add_index :recommendations, :scale
    add_index :recommendations, :grade
  end
end
