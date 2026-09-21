# A figure published by a guideline: a table of diagnostic criteria, a management
# algorithm, a clinical scale.
#
# These are not the images an ENARM item usually hangs on — the live corpus has no ECG
# tracings and no radiographs, only reference material — but they are the ones the
# guideline itself points a reader at, and roughly one recommendation in twelve says
# "ver cuadro 2" without the reader having any way to see cuadro 2. That is the gap this
# fills.
#
# The file is stored rather than linked. The site that serves it replaced an institution
# that was dissolved, and the whole ingestion layer assumes it can vanish again.
class ClinicalImage < ApplicationRecord
  belongs_to :guideline_section
  has_one :guideline, through: :guideline_section
  has_many :clinical_cases, dependent: :nullify

  has_one_attached :file

  enum :kind,
    { table: "table", algorithm: "algorithm", scale: "scale", figure: "figure" },
    prefix: :kind

  enum :source, { gpc: "gpc" }, prefix: :source

  validates :label, presence: true
  validates :position, presence: true, uniqueness: { scope: :guideline_section_id }
  validates :remote_path, presence: true
  validates :attribution, presence: true

  scope :stored, -> { joins(:file_attachment) }

  # What a recommendation writes when it refers to this figure — "cuadro 2", "algoritmo
  # 1". Matching is done on this rather than on the label itself because guidelines are
  # inconsistent about case and about accents in the body text.
  REFERENCE = /\b(cuadro|tabla|algoritmo|diagrama|figura|escala)\s+([0-9]+)/

  def reference_key
    self.class.reference_key(label)
  end

  def self.reference_keys(text)
    I18n.transliterate(text.to_s).downcase.squish.scan(REFERENCE).map { |word, number| "#{word} #{number}" }
  end

  def self.reference_key(label)
    reference_keys(label).first
  end

  # The recommendation in this batch that points at a figure we actually hold, and that
  # figure. A guideline keeps its figures in the anexos rather than inside the statement
  # that refers to them, so "ver cuadro 2" is the only link between the two — and it is a
  # good one: 501 of the 511 recommendations that cite a figure by number cite one the
  # corpus has.
  def self.cited_by(recommendations)
    available = available_for(recommendations)
    return if available.empty?

    recommendations.each do |recommendation|
      image = reference_keys(recommendation.text).filter_map { |key| available[key] }.first
      return [recommendation, image] if image
    end
    nil
  end

  # Only figures whose file actually downloaded, and only from the guideline these
  # recommendations belong to. A figure numbered 2 in another guideline is a different
  # figure entirely.
  def self.available_for(recommendations)
    guideline_id = recommendations.first&.guideline_section&.guideline_id
    return {} if guideline_id.nil?

    stored.joins(:guideline_section)
          .where(guideline_sections: { guideline_id: guideline_id })
          .select(&:reference_key)
          .index_by(&:reference_key)
  end

  # The heading names the type: "CUADRO 6", "ALGORITMO 1", "ESCALA DE GLASGOW".
  KIND_BY_LABEL = {
    /\A(CUADRO|TABLA)/ => "table",
    /\A(ALGORITMO|DIAGRAMA|FLUJOGRAMA)/ => "algorithm",
    /\AESCALA/ => "scale"
  }.freeze

  def self.kind_for(label)
    normalized = I18n.transliterate(label.to_s).upcase
    KIND_BY_LABEL.find { |pattern, _| normalized.match?(pattern) }&.last || "figure"
  end
end
