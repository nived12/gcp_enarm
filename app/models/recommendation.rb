# A single graded statement: the text, plus the evidence grade, the scale that grade
# belongs to, and the study it rests on.
#
# This is the unit a generated question cites. The anti-hallucination gate in Phase 2
# checks a question's source_quote against #text, so #text must stay exactly what the
# guideline published — never cleaned up, never paraphrased.
class Recommendation < ApplicationRecord
  belongs_to :guideline_section
  has_one :guideline, through: :guideline_section

  validates :text, presence: true
  validates :label, presence: true
  validates :position, presence: true, uniqueness: { scope: :guideline_section_id }

  scope :actionable, -> { joins(:guideline_section).merge(GuidelineSection.actionable) }
  scope :with_scale, ->(scale) { where(scale: scale) }

  def cited_as
    [grade, scale, citation].compact_blank.join(" · ").presence || label
  end
end
