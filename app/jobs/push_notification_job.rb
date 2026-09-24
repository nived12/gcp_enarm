class PushNotificationJob < ApplicationJob
  queue_as :default

  retry_on WebPush::TooManyRequests, WebPush::PushServiceError, Net::OpenTimeout, Net::ReadTimeout,
    wait: :polynomially_longer, attempts: 3

  # The subscription was deleted between the dispatch and this run — by a 410 on another
  # reminder, or by the student turning the device off. Nothing is owed to it.
  discard_on ActiveJob::DeserializationError

  def perform(subscription, payload, ttl)
    PushNotifications::Sender.call(subscription: subscription, payload: payload, ttl: ttl)
  end
end
