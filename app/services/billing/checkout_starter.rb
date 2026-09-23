# Opens a hosted Checkout page for one plan and returns its URL. The purchase itself is
# recorded later, by the webhook: returning from Checkout proves nothing, since a student
# can close the tab before being redirected, and OXXO is paid days afterwards.
module Billing
  class CheckoutStarter < ApplicationService
    def initialize(user:, plan_code:, success_url:, cancel_url:, adapter: StripeAdapter.new)
      super()
      @user = user
      @plan_code = plan_code
      @success_url = success_url
      @cancel_url = cancel_url
      @adapter = adapter
    end

    def call
      return failure(I18n.t("billing.checkout.unavailable")) unless StripeAdapter.checkout_available?

      plan = Plan.find(plan_code)
      return failure(I18n.t("billing.checkout.unknown_plan")) unless plan

      url = adapter.create_checkout_session(user: user, plan: plan, success_url: success_url, cancel_url: cancel_url)
      Analytics.capture(user, "checkout_started", plan: plan.code, amount: plan.price)
      success(url: url)
    rescue ::Stripe::StripeError => error
      Sentry.capture_exception(error)
      failure(I18n.t("billing.checkout.failed"))
    end

    def context_for_logging
      { user_id: user.id, plan_code: plan_code }
    end

    private

    attr_reader :user, :plan_code, :success_url, :cancel_url, :adapter
  end
end
