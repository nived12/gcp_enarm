# Records one purchased window. Provider-agnostic on purpose: a Stripe webhook calls it
# today, and an Apple receipt or a Pay callback would call it the same way.
#
# Buying while a window is still open extends it: the new window starts where the
# latest one ends, so nobody loses days by renewing early. Granted premium is not a
# window and is ignored here — it can be withdrawn, and paid days must not hide behind it.
# So is a refunded window: its days were given back, and nothing may queue behind them.
module Billing
  class EntitlementGranter < ApplicationService
    def initialize(user:, plan:, source:, external_id:, amount:, currency:, raw_payload: {})
      super()
      @user = user
      @plan = plan
      @source = source
      @external_id = external_id
      @amount = amount
      @currency = currency
      @raw_payload = raw_payload
    end

    def call
      existing = Entitlement.find_by(source: source, external_id: external_id)
      return success(entitlement: existing, created: false) if existing

      # Two purchases landing at once would both read the same "latest end" and overlap.
      entitlement = user.with_lock { create_entitlement }
      success(entitlement: entitlement, created: true)
    end

    private

    attr_reader :user, :plan, :source, :external_id, :amount, :currency, :raw_payload

    def create_entitlement
      starts_at = [ Time.current, user.entitlements.in_force.maximum(:expires_at) ].compact.max
      user.entitlements.create!(
        plan: plan.code, source: source, external_id: external_id,
        starts_at: starts_at, expires_at: starts_at + plan.months.months,
        amount: amount, currency: currency, raw_payload: raw_payload
      )
    end
  end
end
