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
end
