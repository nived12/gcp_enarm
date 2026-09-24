# Called by the push-subscription Stimulus controller once the browser has granted
# permission and PushManager.subscribe has answered. A browser keeps one subscription
# whoever is signed in, so an endpoint already on file moves to the current account
# rather than being refused: reminders follow whoever uses the device now.
class PushSubscriptionsController < ApplicationController
  before_action :require_web_push

  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    keys = subscription_params.fetch(:keys, {})
    saved = subscription.update(
      user: Current.user, p256dh_key: keys[:p256dh], auth_key: keys[:auth], user_agent: request.user_agent
    )
    head(saved ? :created : :unprocessable_content)
  end

  def destroy
    Current.user.push_subscriptions.where(endpoint: params.expect(:endpoint)).delete_all
    head :no_content
  end

  private

  def require_web_push
    head :not_found unless PushSubscription.enabled?
  end

  def subscription_params
    params.expect(push_subscription: [:endpoint, { keys: %i[p256dh auth] }])
  end
end
