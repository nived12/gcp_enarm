class Guideline < ApplicationRecord
  has_many :guideline_sections, -> { order(:position) }, dependent: :destroy, inverse_of: :guideline
  has_many :recommendations, through: :guideline_sections

  # SS is the Secretaría de Salud; the rest are institution acronyms that read the
  # same in any language, so they stay as they are.
  enum :institution,
    { imss: "imss", health_ministry: "ss", issste: "issste",
      dif: "dif", sedena: "sedena", semar: "semar" },
    prefix: :institution

  enum :source, { live_site: "live_site", web_archive: "web_archive" }, prefix: :source

  validates :catalog_key, presence: true, uniqueness: true
  validates :title, presence: true
  validates :content_hash, presence: true

  scope :with_specialty_label, ->(label) { where("specialty_labels @> ?", [label].to_json) }

  # IMSS-028-22 → imss. The prefix is the only place the publishing institution
  # appears in the catalog, so it is derived rather than scraped.
  def self.institution_from_catalog_key(catalog_key)
    prefix = catalog_key.to_s.split("-").first.to_s.downcase
    institutions.key(prefix)
  end
end
