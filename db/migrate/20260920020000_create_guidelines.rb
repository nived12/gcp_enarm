class CreateGuidelines < ActiveRecord::Migration[8.1]
  def change
    create_table :guidelines do |t|
      t.string :catalog_key, null: false
      t.string :title, null: false
      t.string :institution, null: false
      t.integer :year
      t.string :source, null: false

      # external_id is the live site's DocumentoID. It is theirs, not ours, and it
      # is not stable across their redeploys — catalog_key is the identity.
      t.string :external_id
      t.string :catalog_url
      t.string :document_url

      t.jsonb :levels_of_care, null: false, default: []
      t.jsonb :specialty_labels, null: false, default: []

      # Digest of the parsed attributes. Re-ingestion compares this rather than
      # writing every row on every run, so ingested_at means "we saw it" and
      # updated_at means "it actually changed".
      t.string :content_hash, null: false
      t.datetime :ingested_at

      t.timestamps
    end

    add_index :guidelines, :catalog_key, unique: true
    add_index :guidelines, :institution
    add_index :guidelines, :year
    add_index :guidelines, :specialty_labels, using: :gin
  end
end
