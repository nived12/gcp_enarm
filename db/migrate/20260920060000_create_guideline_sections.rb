class CreateGuidelineSections < ActiveRecord::Migration[8.1]
  def change
    create_table :guideline_sections do |t|
      t.references :guideline, null: false, foreign_key: true

      # The site's own data-id for the section. Unlike the guideline's DocumentoID
      # this is what the content endpoint takes, so it is worth keeping even though
      # the (guideline, position) pair is our real identity.
      t.string :external_id, null: false

      t.string :heading, null: false

      # The PICO question a block of evidencias/recomendaciones answers, lifted from
      # the section's own <h2>. Null on sections that are not part of a question —
      # objetivos, anexos, cuadros.
      t.text :clinical_question

      t.string :kind, null: false
      t.integer :position, null: false
      t.text :body, null: false
      t.string :content_hash, null: false

      t.timestamps
    end

    add_index :guideline_sections, [:guideline_id, :external_id], unique: true
    add_index :guideline_sections, [:guideline_id, :position]
    add_index :guideline_sections, :kind
  end
end
