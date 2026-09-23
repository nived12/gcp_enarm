# Verifies a Stripe webhook and turns a paid Checkout Session into an Entitlement, and a
# refunded charge into a refund on the Entitlement it paid for.
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
      refund = adapter.refund_from(event)
      return record_refund(refund) if refund

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

    # The PaymentIntent is the charge's only link to a sale, and every sale kept it in its
    # Checkout Session payload. A refund we cannot place is answered with an error, so it
    # stays visible and retried in the dashboard rather than silently dropped.
    def record_refund(refund)
      entitlement = refund[:payment_intent] &&
        Entitlement.source_stripe.find_by("raw_payload ->> 'payment_intent' = ?", refund[:payment_intent])
      return failure(I18n.t("billing.webhook.unmatched_refund")) unless entitlement

      result = RefundRecorder.call(entitlement: entitlement, **refund.slice(:refunded_amount, :full))
      if result.payload[:revoked]
        Analytics.capture(
          entitlement.user, "purchase_refunded", plan: entitlement.plan,
          amount: entitlement.amount.to_f
        )
      end
      success(status: :refunded, entitlement: entitlement)
    end
  end
end
