FactoryBot.define do
  factory :reminder_preference do
    user
    minute_of_day { 8 * 60 }
  end

  # Real key material: the web-push gem encrypts every payload against p256dh and auth,
  # so anything that is not a P-256 point fails before a request is ever made.
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://fcm.googleapis.com/fcm/send/device-#{n}" }
    p256dh_key { Base64.urlsafe_encode64(OpenSSL::PKey::EC.generate("prime256v1").public_key.to_bn.to_s(2)) }
    auth_key { Base64.urlsafe_encode64(SecureRandom.random_bytes(16)) }
  end

  factory :reminder_delivery do
    user
    local_date { Date.new(2026, 10, 6) }
    kind { "study_day" }
    slot { "daily" }
  end
end
