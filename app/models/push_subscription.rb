# One browser a student allowed to show notifications, as PushManager.subscribe returned
# it. The server will POST to `endpoint`, which the browser chose — so only the push
# services browsers actually use are accepted, or a forged subscription would turn the
# reminder job into a way to make this server request any URL.
class PushSubscription < ApplicationRecord
  belongs_to :user

  # Chrome, Edge-on-Android, Samsung Internet and Opera use Firebase; Firefox uses
  # Mozilla's autopush; Safari on macOS and iOS uses Apple's; Edge on Windows uses WNS.
  PUSH_SERVICE_HOSTS = %w[
    fcm.googleapis.com android.googleapis.com push.services.mozilla.com push.apple.com notify.windows.com
  ].freeze

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true
  validate :endpoint_is_a_push_service

  # Web Push is invisible until the VAPID pair exists: without it nothing can be signed,
  # so offering the button would only produce subscriptions that never receive anything.
  def self.enabled?
    ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
  end

  def self.public_key
    ENV.fetch("VAPID_PUBLIC_KEY")
  end

  def self.vapid
    {
      subject: ENV.fetch("VAPID_SUBJECT", "mailto:soporte@gpcenarm.com"),
      public_key: ENV.fetch("VAPID_PUBLIC_KEY"),
      private_key: ENV.fetch("VAPID_PRIVATE_KEY")
    }
  end

  private

  def endpoint_is_a_push_service
    uri = URI.parse(endpoint.to_s)
    host = uri.host.to_s.downcase
    known = PUSH_SERVICE_HOSTS.any? { |service| host == service || host.end_with?(".#{service}") }
    errors.add(:endpoint, :invalid) unless uri.is_a?(URI::HTTPS) && known
  rescue URI::InvalidURIError
    errors.add(:endpoint, :invalid)
  end
end
