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

  scope :with_specialty_label, ->(label) { where("specialty_labels @> ?", [label].to_json) }

  # IMSS-028-22 → imss. The prefix is the only place the publishing institution
  # appears in the catalog, so it is derived rather than scraped.
  # CENETEC spelled the Secretaría de Salud "S-" before roughly 2016 and "SS-" after,
  # e.g. S-102-08 and SS-102-22 are the same institution and, there, the same guideline.
  CATALOG_KEY_PREFIX_ALIASES = { "s" => "ss" }.freeze

  def self.institution_from_catalog_key(catalog_key)
    prefix = catalog_key.to_s.split("-").first.to_s.downcase
    institutions.key(CATALOG_KEY_PREFIX_ALIASES.fetch(prefix, prefix))
  end
end
