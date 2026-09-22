class AddSourceSectionToGuidelineSections < ActiveRecord::Migration[8.1]
  def change
    add_reference :guideline_sections, :source_section, foreign_key: { to_table: :guideline_sections }
  end
end
