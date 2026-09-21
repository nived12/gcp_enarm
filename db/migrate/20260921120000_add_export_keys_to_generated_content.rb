class AddExportKeysToGeneratedContent < ActiveRecord::Migration[8.1]
  # A generated case has no natural key. Its content is arbitrary text that the model
  # will never write the same way twice, so there is nothing about it to match on when
  # the same batch arrives in another database — and unlike the scraped corpus, it cannot
  # be fetched again to find out. The token is the identity that survives the move, and it
  # is what makes importing the same file twice a no-op instead of a duplication.
  def up
    add_column :generation_runs, :export_key, :string
    add_column :clinical_cases, :export_key, :string

    execute "UPDATE generation_runs SET export_key = gen_random_uuid() WHERE export_key IS NULL"
    execute "UPDATE clinical_cases SET export_key = gen_random_uuid() WHERE export_key IS NULL"

    change_column_null :generation_runs, :export_key, false
    change_column_null :clinical_cases, :export_key, false
    add_index :generation_runs, :export_key, unique: true
    add_index :clinical_cases, :export_key, unique: true
  end

  def down
    remove_column :generation_runs, :export_key
    remove_column :clinical_cases, :export_key
  end
end
