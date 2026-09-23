# The only code that talks to Stripe. Every other class — the services beside this one
# included — hands it our own Plan and User and gets plain values back, so adding Apple
# or the Pay gem later is one more adapter, not a change to the app.
#
# Credentials are read on every call, never at boot: the app must start and run with no
# Stripe keys at all, and it does — checkout reports itself unavailable.
module Billing
  class StripeAdapter
    CHECKOUT_COMPLETED = "checkout.session.completed".freeze
    ASYNC_PAYMENT_SUCCEEDED = "checkout.session.async_payment_succeeded".freeze
    CHARGE_REFUNDED = "charge.refunded".freeze

    def self.checkout_available?
      secret_key.present?
    end

    def self.secret_key
      ENV["STRIPE_SECRET_KEY"].presence
    end

    def self.webhook_secret
      ENV["STRIPE_WEBHOOK_SECRET"].presence
    end

    # Prices travel inline as price_data rather than as dashboard Price ids, so the amount
    # charged is the one Plan shows on the pricing page and there is nothing to keep in
    # sync. No payment_method_types: the dashboard decides, which is where OXXO is enabled.
    #
    # No `locale` either, so Checkout follows the browser. stripe 19.6.2 (API
    # 2026-08-26.dahlia) types it as a free String and lists no accepted values, so
    # "es-419" could not be confirmed from the bundle; confirm it in Stripe's docs first.
    def create_checkout_session(user:, plan:, success_url:, cancel_url:)
      metadata = { user_id: user.id.to_s, plan_code: plan.code }
      session = client.v1.checkout.sessions.create(
        mode: "payment",
        line_items: [ { quantity: 1, price_data: price_data(plan) } ],
        client_reference_id: user.id.to_s,
        customer_email: user.email,
        metadata: metadata,
        payment_intent_data: { metadata: metadata },
        success_url: success_url,
        cancel_url: cancel_url
      )
      session.url
    end

    # Raises Stripe::SignatureVerificationError for a missing, stale or forged signature,
    # and for a missing webhook secret — an unconfigured endpoint trusts nothing.
    def verified_event(payload, signature)
      ::Stripe::Webhook.construct_event(payload, signature.to_s, self.class.webhook_secret.to_s)
    end

    # A paid Checkout Session, reduced to what an Entitlement needs. OXXO completes the
    # session unpaid and pays days later in a second event, so "completed" alone is not
    # a sale.
    def purchase_from(event)
      session = event.data.object
      return unless paid?(event, session)

      { user_id: session.client_reference_id, plan_code: session.metadata[:plan_code], external_id: session.id,
        amount: BigDecimal(session.amount_total.to_s) / 100, currency: session.currency.to_s.upcase,
        raw_payload: session.to_hash }
    end

    # A refunded charge, reduced to what a refund needs. Stripe sends `charge.refunded`
    # for partial refunds too; `refunded` turns true only once the whole charge is back,
    # and `amount_refunded` is the running total across every refund of the charge.
    def refund_from(event)
      return unless event.type == CHARGE_REFUNDED

      charge = event.data.object
      { payment_intent: charge.payment_intent, refunded_amount: BigDecimal(charge.amount_refunded.to_s) / 100,
        full: charge.refunded == true }
    end

    private

    def paid?(event, session)
      case event.type
      when CHECKOUT_COMPLETED then session.payment_status == "paid"
      when ASYNC_PAYMENT_SUCCEEDED then true
      else false
      end
    end

    def price_data(plan)
      { currency: plan.currency.downcase, unit_amount: plan.amount_in_cents,
        product_data: { name: I18n.t("billing.plans.#{plan.code}.product_name", locale: :es) } }
    end

    def client
      ::Stripe::StripeClient.new(self.class.secret_key)
    end
  end
end
