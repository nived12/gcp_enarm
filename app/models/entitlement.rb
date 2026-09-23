# A window of paid access. Rows are append-only: a second purchase adds a row, so this
# table is the purchase ledger. Only services under app/services/billing write it, and
# nothing outside them knows which provider a row came from beyond `source`.
class Entitlement < ApplicationRecord
  belongs_to :user

  enum :plan, Plan.codes.index_with(&:itself), prefix: :plan
  enum :source, { stripe: "stripe", apple: "apple", granted: "granted" }, prefix: :source

  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :starts_at, :expires_at, presence: true
  validate :expires_after_start

  scope :active_at, ->(time) { where(starts_at: ..time).where("expires_at > ?", time) }
  scope :unexpired, -> { where("expires_at > ?", Time.current) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def catalog_plan
    Plan.find(plan)
  end

  private

  def expires_after_start
    return if starts_at.blank? || expires_at.blank? || expires_at > starts_at

    errors.add(:expires_at, :greater_than, count: starts_at)
  end
end
