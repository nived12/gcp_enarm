# One of the seven blocks the ENARM is built from: the four troncales and the three
# transversal contexts the convocatoria names.
class Specialty < ApplicationRecord
  has_many :branches, -> { order(:position) }, dependent: :destroy, inverse_of: :specialty
  has_many :topics, through: :branches

  enum :kind, { core: "core", cross_cutting: "cross_cutting" }, prefix: :kind

  # Names of tokens defined in application.tailwind.css. The palette lives in CSS; this
  # only says which entry a specialty uses, so dark mode stays a stylesheet concern.
  COLOR_TOKENS = %w[indigo green magenta amber teal red violet].freeze

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :position, presence: true
  validates :color_token, inclusion: { in: COLOR_TOKENS }

  scope :in_reading_order, -> { order(:position) }

  # The code a generation prompt asks the model for, by the slug of the setting it names.
  # A fixed English code rather than the name: the model answers in whatever language the
  # case is in, and "Urgencias", "urgencias médicas" and "emergency" must all mean one row.
  SETTING_SLUGS = {
    "family_medicine" => "medicina-familiar",
    "emergency" => "urgencias",
    "public_health" => "salud-publica"
  }.freeze

  # Nil for a code that is not one of the three, and for a taxonomy that lacks the row:
  # an unknown setting is left unknown rather than guessed.
  def self.for_setting_code(code)
    slug = SETTING_SLUGS[code.to_s.strip.downcase]
    kind_cross_cutting.find_by(slug: slug) if slug
  end

  def setting_code
    SETTING_SLUGS.key(slug)
  end
end
