# Sends one payload to one subscribed browser.
#
# A push service answering 404 or 410 is saying the subscription is gone — the student
# revoked permission, uninstalled the home-screen app or cleared the browser — and will
# never come back, so the row is deleted. Throttling and server errors are the push
# service's own trouble and are raised for PushNotificationJob to retry.
module PushNotifications
  class Sender < ApplicationService
    def initialize(subscription:, payload:, ttl:)
      super()
      @subscription = subscription
      @payload = payload
      @ttl = ttl
    end

    def call
      WebPush.payload_send(
        message: payload, endpoint: subscription.endpoint, p256dh: subscription.p256dh_key,
        auth: subscription.auth_key, vapid: PushSubscription.vapid, ttl: ttl
      )
      success
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy!
      failure("Subscription #{subscription.id} is gone; deleted")
    rescue WebPush::TooManyRequests, WebPush::PushServiceError
      raise
    rescue WebPush::ResponseError => error
      failure("Push to subscription #{subscription.id} refused: #{error.response.code}")
    end

    private

    attr_reader :subscription, :payload, :ttl
  end
end
