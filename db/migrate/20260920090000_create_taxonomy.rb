class CreateTaxonomy < ActiveRecord::Migration[8.1]
  def change
    create_table :specialties do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :kind, null: false

      # The name of a token defined in application.tailwind.css, never a hex value:
      # the palette lives in CSS and this column only says which entry to use.
      t.string :color_token, null: false

      t.integer :position, null: false
      t.timestamps
    end

    create_table :branches do |t|
      t.references :specialty, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false
      t.timestamps
    end

    create_table :topics do |t|
      t.references :branch, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false

      # Other names the same thing goes by, so a guideline titled "cetoacidosis
      # diabética" still matches the topic a student knows as "complicaciones agudas
      # de la diabetes".
      t.jsonb :aliases, null: false, default: []

      t.timestamps
    end

    create_table :guideline_topics do |t|
      t.references :guideline, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true

      # How strongly the guideline is about this topic, 0–1. Set by Gpc::TopicLinker
      # from how much of the matched phrase the title actually is.
      t.float :relevance, null: false, default: 0.0

      t.timestamps
    end

    add_index :specialties, :slug, unique: true
    add_index :branches, :slug, unique: true
    add_index :branches, [:specialty_id, :position]
    add_index :topics, :slug, unique: true
    add_index :topics, [:branch_id, :position]
    add_index :guideline_topics, [:guideline_id, :topic_id], unique: true
    add_index :guideline_topics, :relevance
  end
end
