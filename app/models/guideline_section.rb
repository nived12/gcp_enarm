# One entry in a guideline's table of contents, with the HTML the site returns for it.
#
# The four graded kinds below are the ones worth generating from; everything else —
# cuadros, algoritmos, bibliografía, the AGREE II appraisal — is stored so the
# guideline can be re-parsed without hitting the site again, and ignored otherwise.
class GuidelineSection < ApplicationRecord
  belongs_to :guideline
  has_many :recommendations, -> { order(:position) }, dependent: :destroy, inverse_of: :guideline_section

  enum :kind,
    { evidence: "evidence", recommendation: "recommendation",
      key_recommendation: "key_recommendation", good_practice: "good_practice",
      other: "other" },
    prefix: :kind

  # The kinds that state what a clinician should do. Evidence sections are graded
  # too, but they describe studies rather than prescribe care, so a question that
  # cites one has to be worded differently.
  ACTIONABLE_KINDS = %w[recommendation key_recommendation good_practice].freeze

  validates :external_id, presence: true, uniqueness: { scope: :guideline_id }
  validates :heading, presence: true
  validates :position, presence: true
  validates :content_hash, presence: true

  scope :actionable, -> { where(kind: ACTIONABLE_KINDS) }
  scope :graded, -> { where(kind: ACTIONABLE_KINDS + ["evidence"]) }

  # The site's menu labels every section in Spanish and repeats the same handful of
  # words across all 53 guidelines, so the kind is read off the label rather than
  # from any attribute the site exposes.
  KIND_BY_HEADING = {
    /\ARECOMENDACIONES CLAVE/ => "key_recommendation",
    /\ARECOMENDACIONES/ => "recommendation",
    /\AEVIDENCIAS/ => "evidence",
    /\APUNTOS DE BUENA PR[ÁA]CTICA/ => "good_practice"
  }.freeze

  def self.kind_from_heading(heading)
    normalized = heading.to_s.squish.upcase
    KIND_BY_HEADING.find { |pattern, _| normalized.match?(pattern) }&.last || "other"
  end
end
