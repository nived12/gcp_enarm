FactoryBot.define do
  factory :entitlement do
    user
    plan { "one_month" }
    source { "stripe" }
    sequence(:external_id) { |n| "cs_test_#{n}" }
    starts_at { Time.current }
    expires_at { starts_at + 1.month }
    amount { 199 }
    currency { "MXN" }
  end
end
