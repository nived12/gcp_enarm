# A subdivision of a specialty — Cardiología under Medicina Interna. ENARMaster's
# simulator calls these ramas and so does Dr. Re's temario.
class Branch < ApplicationRecord
  belongs_to :specialty
  has_many :topics, -> { order(:position) }, dependent: :destroy, inverse_of: :branch

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :position, presence: true
end
