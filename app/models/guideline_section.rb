# One entry in a guideline's table of contents, with the HTML the site returns for it.
#
# An archived guideline has no table of contents — it is a PDF — so it gets a single
# section of kind archived_document holding the whole extracted text.
#
# The four graded kinds below are the ones worth generating from; everything else —
# cuadros, algoritmos, bibliografía, the AGREE II appraisal — is stored so the
# guideline can be re-parsed without hitting the site again, and ignored otherwise.
class GuidelineSection < ApplicationRecord
  belongs_to :guideline
  has_many :recommendations, -> { order(:position) }, dependent: :destroy, inverse_of: :guideline_section
  has_many :clinical_images, -> { order(:position) }, dependent: :destroy, inverse_of: :guideline_section

  enum :kind,
    { evidence: "evidence", recommendation: "recommendation",
      key_recommendation: "key_recommendation", good_practice: "good_practice",
      archived_document: "archived_document", other: "other" },
    prefix: :kind

  # The kinds that state what a clinician should do. Evidence sections are graded
  # too, but they describe studies rather than prescribe care, so a question that
  # cites one has to be worded differently.
  ACTIONABLE_KINDS = %w[recommendation key_recommendation good_practice].freeze

  # Everything above plus evidence. Outside these, a div.separador is not a grading
  # strip at all — the anexos use it for directory entries and for the tables that
  # define the scales — so nothing else is parsed for recommendations.
  GRADED_KINDS = (ACTIONABLE_KINDS + ["evidence"]).freeze

  validates :external_id, presence: true, uniqueness: { scope: :guideline_id }
  validates :heading, presence: true
  validates :position, presence: true
  validates :content_hash, presence: true

  scope :actionable, -> { where(kind: ACTIONABLE_KINDS) }
  scope :graded, -> { where(kind: GRADED_KINDS) }

  # The site's menu labels every section in Spanish and repeats the same handful of
  # words across all 53 guidelines, so the kind is read off the label rather than
  # from any attribute the site exposes.
  KIND_BY_HEADING = {
    /\ARECOMENDACIONES CLAVE/ => "key_recommendation",
    /\ARECOMENDACIONES/ => "recommendation",
    /\AEVIDENCIAS/ => "evidence",
    /\APUNTOS DE BUENA PR[ÁA]CTICA/ => "good_practice"
  }.freeze

  # The path a reader has to click on the live site to reach this section:
  # "FACTORES DE RIESGO › PREGUNTA 1 › RECOMENDACIONES CLAVE". The site's menu is a
  # two-level accordion with no addressable sections, so repeating its own wording is
  # the only way a citation can point at anything narrower than the whole guideline.
  def menu_path
    [chapter, question_label, heading].compact_blank.join(" › ")
  end

  def graded?
    GRADED_KINDS.include?(kind)
  end

  def self.kind_from_heading(heading)
    normalized = heading.to_s.squish.upcase
    KIND_BY_HEADING.find { |pattern, _| normalized.match?(pattern) }&.last || "other"
  end
end
