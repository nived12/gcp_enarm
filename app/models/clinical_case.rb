# A clinical vignette and the two or three questions asked about it.
#
# The convocatoria is explicit that every ENARM item is a case with 2–3 questions, one
# correct option and three distractors, so the case is the unit throughout — exams select
# whole cases, never orphan questions.
class ClinicalCase < ApplicationRecord
  include Exportable

  belongs_to :topic, optional: true
  belongs_to :specialty, optional: true
  belongs_to :guideline, optional: true
  belongs_to :generation_run, optional: true
  belongs_to :clinical_image, optional: true

  has_many :questions, -> { order(:position) }, dependent: :destroy, inverse_of: :clinical_case

  # CIFRHS's own vocabulary, rendered Baja / Media / Alta. Never a competitor's invented
  # Interno / Residente / Adscrito: difficulty is what actually breaks ties on the real
  # exam, and the simulator should teach the student the axis they will be ranked on.
  enum :difficulty,
    { low: "low", medium: "medium", high: "high" },
    prefix: :difficulty

  enum :status,
    { draft: "draft", published: "published", flagged: "flagged", retired: "retired" },
    prefix: :status

  enum :source,
    { gpc_generated: "gpc_generated", authored: "authored", imported: "imported" },
    prefix: :source

  enum :verification_verdict,
    { supported: "supported", unsupported: "unsupported", ambiguous: "ambiguous" },
    prefix: :verdict

  validates :stem, presence: true
  validates :locale, presence: true

  scope :publishable, -> { where(verification_verdict: "supported") }

  # A case may only go live once a second model family has agreed its correct answer is
  # actually supported by the quote it cites. Unverified and unsupported both stay back:
  # silence from the verifier is not assent.
  def publishable?
    verdict_supported?
  end
end
