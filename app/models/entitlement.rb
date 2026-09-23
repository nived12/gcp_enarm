# A window of paid access. Rows are append-only: a second purchase adds a row, so this
# table is the purchase ledger. Only services under app/services/billing write it, and
# nothing outside them knows which provider a row came from beyond `source`.
#
# A refund is written onto the purchase it reverses rather than as a row of its own, so
# every access query stays one WHERE clause instead of subtracting windows. What was sold
# (plan, amount, starts_at, expires_at) is never rewritten on the refunded row itself;
# see Billing::RefundRecorder for the later windows it moves.
class Entitlement < ApplicationRecord
  belongs_to :user

  enum :plan, Plan.codes.index_with(&:itself), prefix: :plan
  enum :source, { stripe: "stripe", apple: "apple", granted: "granted" }, prefix: :source

  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :starts_at, :expires_at, presence: true
  validate :expires_after_start

  # Everything that still grants access. A fully refunded window grants nothing, from
  # the moment of the refund, whatever its dates say.
  scope :in_force, -> { where(refunded_at: nil) }
  scope :active_at, ->(time) { where(starts_at: ..time).where("expires_at > ?", time) }
  scope :unexpired, -> { where("expires_at > ?", Time.current) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def catalog_plan
    Plan.find(plan)
  end

  def refunded?
    refunded_at.present?
  end

  def partially_refunded?
    !refunded? && refunded_amount.positive?
  end

  private

  def expires_after_start
    return if starts_at.blank? || expires_at.blank? || expires_at > starts_at

    errors.add(:expires_at, :greater_than, count: starts_at)
  end
end
