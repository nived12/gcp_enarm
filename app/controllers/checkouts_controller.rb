# Sends the student to the provider's hosted payment page for one plan. Access is
# granted by the webhook, not by coming back from here.
class CheckoutsController < ApplicationController
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> {
    redirect_to pricing_path, alert: t("sessions.create.rate_limited")
  }

  def create
    result = Billing::CheckoutStarter.call(
      user: Current.user, plan_code: params[:plan],
      success_url: account_url(checkout: "success"), cancel_url: pricing_url
    )
    return redirect_to(pricing_path, alert: result.errors.full_messages.to_sentence) if result.failure?

    redirect_to result.payload[:url], allow_other_host: true, status: :see_other
  end
end
