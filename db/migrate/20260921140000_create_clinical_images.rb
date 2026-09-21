class CreateClinicalImages < ActiveRecord::Migration[8.1]
  def change
    # The figures a guideline publishes alongside its recommendations: cuadros de
    # criterios, algoritmos de manejo, escalas clínicas. They live in their own anexo
    # sections rather than inside the recommendation that refers to them, so they are
    # their own rows and are matched back to a recommendation by the label it cites.
    create_table :clinical_images do |t|
      t.references :guideline_section, null: false, foreign_key: true, index: true

      # What the guideline calls it — "CUADRO 2", "ALGORITMO 1". This is the string a
      # recommendation uses when it says "ver cuadro 2", so it is the join key between
      # a statement and its figure, and it is stored exactly as published.
      t.string :label, null: false
      t.string :caption
      t.string :kind, null: false, default: "figure"

      # Position within its section: one anexo can hold a figure split across several
      # files (cuadro_6_1.jpg, cuadro_6_2.jpg).
      t.integer :position, null: false

      # The path on the source site, kept so a re-run can tell which files it already
      # has without downloading them again.
      t.string :remote_path, null: false

      # A licence condition rather than a nicety, so it is a column and not something a
      # view is trusted to remember.
      t.string :attribution, null: false
      t.string :source, null: false, default: "gpc"

      t.timestamps
    end

    add_index :clinical_images, %i[guideline_section_id position], unique: true
    add_index :clinical_images, :label
    add_index :clinical_images, :kind

    # A case carries at most one figure, the way a real exam item carries one tracing or
    # one film. Chosen before generation, never after: the vignette has to lead into the
    # image for the item to read like an exam item.
    add_reference :clinical_cases, :clinical_image, foreign_key: true, index: true
  end
end
