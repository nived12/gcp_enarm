class Guideline < ApplicationRecord
  has_many :guideline_sections, -> { order(:position) }, dependent: :destroy, inverse_of: :guideline
  has_many :recommendations, through: :guideline_sections
  has_many :guideline_topics, dependent: :destroy
  has_many :topics, through: :guideline_topics

  # SS is the Secretaría de Salud; the rest are institution acronyms that read the
  # same in any language, so they stay as they are.
  enum :institution,
    { imss: "imss", health_ministry: "ss", issste: "issste",
      dif: "dif", sedena: "sedena", semar: "semar" },
    prefix: :institution

  enum :source, { live_site: "live_site", web_archive: "web_archive" }, prefix: :source

  validates :catalog_key, presence: true, uniqueness: true
  # A catalog key with a prefix we do not know yields a nil institution. Validating it
  # turns that into one recorded failure instead of a NotNullViolation that takes the
  # whole ingestion run down with it.
  validates :institution, presence: true
  validates :source, presence: true
  validates :title, presence: true
  validates :content_hash, presence: true

  # Guidelines state their own shelf life: "Fecha de actualización: de 3 a 5 años a
  # partir de la fecha de ACTUALIZACIÓN", which appears in roughly a third of the
  # archived corpus. Five is the generous end of that range, and being generous is right
  # here — calling a guideline expired that the exam still tests would be the worse error.
  #
  # This is why the live catalog holds nothing older than 2020: when CENETEC was dissolved
  # in 2025 its successor republished only what was still inside this window. The other
  # ~690 guidelines are past it, and Cirugía General exists *only* among them, so expired
  # is a fact to show the student rather than a reason to drop the guideline.
  VALIDITY_YEARS = 5

  scope :current, -> { where(year: oldest_valid_year..) }
  scope :expired, -> { where(year: ...oldest_valid_year) }
  scope :undated, -> { where(year: nil) }

  def self.oldest_valid_year
    Date.current.year - VALIDITY_YEARS
  end

  scope :with_specialty_label, ->(label) { where("specialty_labels @> ?", [label].to_json) }

  # IMSS-028-22 → imss. The prefix is the only place the publishing institution
  # appears in the catalog, so it is derived rather than scraped.
  # CENETEC spelled the Secretaría de Salud "S-" before roughly 2016 and "SS-" after,
  # e.g. S-102-08 and SS-102-22 are the same institution and, there, the same guideline.
  CATALOG_KEY_PREFIX_ALIASES = { "s" => "ss" }.freeze

  # Nil when the year never parsed. Unknown is not the same as expired, and a question
  # generated from it should say so rather than imply currency.
  # Where a student can go and read the guideline for herself.
  #
  # The live site opens the guideline's own page; an archived one opens the Wayback
  # capture rather than the `id_/` raw-bytes form the importer used, because that form
  # serves the PDF without the archive's header saying when it was captured — and the
  # capture date is the honest part.
  def source_url
    source_web_archive? ? catalog_url : document_url
  end

  def expires_on
    Date.new(year + VALIDITY_YEARS, 12, 31) if year
  end

  def expired?
    return false if year.nil?

    year < self.class.oldest_valid_year
  end

  def self.institution_from_catalog_key(catalog_key)
    prefix = catalog_key.to_s.split("-").first.to_s.downcase
    institutions.key(CATALOG_KEY_PREFIX_ALIASES.fetch(prefix, prefix))
  end
end
