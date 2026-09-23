# Stripe's webhook endpoint. ActionController::API because Stripe is not a browser: no
# session, no CSRF token, and nothing for `allow_browser` to judge. Authenticity comes
# from the signature, which Billing::StripeWebhookHandler checks before reading a byte.
class StripeWebhooksController < ActionController::API
  def create
    result = Billing::StripeWebhookHandler.call(
      payload: request.raw_post, signature: request.headers["Stripe-Signature"]
    )
    return head(:ok) if result.success?

    # A bad signature will never verify, so Stripe may as well stop; anything else is
    # answered with an error so Stripe retries it and it shows in the dashboard.
    head(result.errors.of_kind?(:base, :invalid_signature) ? :bad_request : :unprocessable_content)
  end
end
