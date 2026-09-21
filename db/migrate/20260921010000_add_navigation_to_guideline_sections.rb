class AddNavigationToGuidelineSections < ActiveRecord::Migration[8.1]
  def change
    # Where this section sits in the guideline's own menu. The live site is a two-level
    # accordion — chapter, then "PREGUNTA N", then the section itself — and none of those
    # levels has a URL, so a citation can only tell a reader where to click. Storing the
    # site's exact wording is what makes that instruction followable.
    add_column :guideline_sections, :chapter, :string
    add_column :guideline_sections, :question_label, :string
  end
end
