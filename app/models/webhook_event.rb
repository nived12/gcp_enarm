# A provider event we have already acted on. Written in the same transaction as the
# effect, so a replay finds it and an event whose handling failed does not.
class WebhookEvent < ApplicationRecord
  enum :provider, { stripe: "stripe" }, prefix: :provider

  validates :external_id, :event_type, presence: true
end
