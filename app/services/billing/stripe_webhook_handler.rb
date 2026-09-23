# Verifies a Stripe webhook and turns a paid Checkout Session into an Entitlement.
#
# Stripe delivers at least once and retries anything that is not a 2xx, so the event id
# is recorded in the same transaction as its effect: a replay is recognised and
# acknowledged, and an event whose handling failed leaves no trace and is retried.
module Billing
  class StripeWebhookHandler < ApplicationService
    def initialize(payload:, signature:, adapter: StripeAdapter.new)
      super()
      @payload = payload
      @signature = signature
      @adapter = adapter
    end

    def call
      event = adapter.verified_event(payload, signature)
      record(event)
    rescue ::Stripe::SignatureVerificationError
      errors.add(:base, :invalid_signature, message: I18n.t("billing.webhook.invalid_signature"))
      failure
    end

    def context_for_logging
      { event_id: @event_id }.compact
    end

    private

    attr_reader :payload, :signature, :adapter

    def record(event)
      @event_id = event.id
      outcome = nil
      ActiveRecord::Base.transaction do
        WebhookEvent.create!(provider: "stripe", external_id: event.id, event_type: event.type)
        outcome = handle(event)
        raise ActiveRecord::Rollback if outcome.failure?
      end
      outcome
    rescue ActiveRecord::RecordNotUnique
      success(status: :duplicate)
    end

    def handle(event)
      purchase = adapter.purchase_from(event)
      return success(status: :ignored) unless purchase

      user = User.find_by(id: purchase[:user_id])
      plan = Plan.find(purchase[:plan_code])
      return failure(I18n.t("billing.webhook.unmatched")) unless user && plan

      grant(user, plan, purchase)
    end

    def grant(user, plan, purchase)
      result = EntitlementGranter.call(
        user: user, plan: plan, source: "stripe", **purchase.slice(:external_id, :amount, :currency, :raw_payload)
      )
      if result.payload[:created]
        Analytics.capture(user, "purchase_completed", plan: plan.code, amount: purchase[:amount].to_f)
      end
      success(status: :processed, entitlement: result.payload[:entitlement])
    end
  end
end
